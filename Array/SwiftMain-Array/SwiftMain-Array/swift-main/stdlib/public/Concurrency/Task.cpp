//===--- Task.cpp - Task object and management ----------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// Object management routines for asynchronous task objects.
//
//===----------------------------------------------------------------------===//

#include "swift/Runtime/Concurrency.h"
#include "swift/ABI/Task.h"
#include "swift/ABI/TaskLocal.h"
#include "swift/ABI/Metadata.h"
#include "swift/Runtime/Mutex.h"
#include "swift/Runtime/HeapObject.h"
#include "TaskGroupPrivate.h"
#include "TaskPrivate.h"
#include "AsyncCall.h"
#include "Debug.h"

#include <dispatch/dispatch.h>

#if !defined(_WIN32)
#include <dlfcn.h>
#endif

using namespace swift;
using FutureFragment = AsyncTask::FutureFragment;
using TaskGroup = swift::TaskGroup;
using TaskLocalInheritance = TaskLocal::TaskLocalInheritance;

void FutureFragment::destroy() {
  auto queueHead = waitQueue.load(std::memory_order_acquire);
  switch (queueHead.getStatus()) {
  case Status::Executing:
    assert(false && "destroying a task that never completed");

  case Status::Success:
    resultType->vw_destroy(getStoragePtr());
    break;

  case Status::Error:
    swift_unknownObjectRelease(reinterpret_cast<OpaqueValue *>(getError()));
    break;
  }
}

FutureFragment::Status AsyncTask::waitFuture(AsyncTask *waitingTask) {
  using Status = FutureFragment::Status;
  using WaitQueueItem = FutureFragment::WaitQueueItem;

  assert(isFuture());
  auto fragment = futureFragment();

  auto queueHead = fragment->waitQueue.load(std::memory_order_acquire);
  while (true) {
    switch (queueHead.getStatus()) {
    case Status::Error:
    case Status::Success:
      _swift_tsan_acquire(static_cast<Job *>(this));
      // The task is done; we don't need to wait.
      return queueHead.getStatus();

    case Status::Executing:
      _swift_tsan_release(static_cast<Job *>(waitingTask));
      // Task is now complete. We'll need to add ourselves to the queue.
      break;
    }

    // Put the waiting task at the beginning of the wait queue.
    waitingTask->getNextWaitingTask() = queueHead.getTask();
    auto newQueueHead = WaitQueueItem::get(Status::Executing, waitingTask);
    if (fragment->waitQueue.compare_exchange_weak(
            queueHead, newQueueHead,
            /*success*/ std::memory_order_release,
            /*failure*/ std::memory_order_acquire)) {
      // Escalate the priority of this task based on the priority
      // of the waiting task.
      swift_task_escalate(this, waitingTask->Flags.getPriority());
      return FutureFragment::Status::Executing;
    }
  }
}

void AsyncTask::completeFuture(AsyncContext *context) {
  using Status = FutureFragment::Status;
  using WaitQueueItem = FutureFragment::WaitQueueItem;

  assert(isFuture());
  auto fragment = futureFragment();

  // If an error was thrown, save it in the future fragment.
  auto asyncContextPrefix = reinterpret_cast<FutureAsyncContextPrefix *>(
      reinterpret_cast<char *>(context) - sizeof(FutureAsyncContextPrefix));
  bool hadErrorResult = false;
  auto errorObject = asyncContextPrefix->errorResult;
  printf("asyncTask::completeFuture errorObject: %p\n", errorObject);
  fragment->getError() = errorObject;
  if (errorObject) {
    hadErrorResult = true;
  }

  _swift_tsan_release(static_cast<Job *>(this));

  // Update the status to signal completion.
  auto newQueueHead = WaitQueueItem::get(
    hadErrorResult ? Status::Error : Status::Success,
    nullptr
  );
  auto queueHead = fragment->waitQueue.exchange(
      newQueueHead, std::memory_order_acquire);
  assert(queueHead.getStatus() == Status::Executing);

  // If this is task group child, notify the parent group about the completion.
  if (hasGroupChildFragment()) {
    // then we must offer into the parent group that we completed,
    // so it may `next()` poll completed child tasks in completion order.
    auto group = groupChildFragment()->getGroup();
    group->offer(this, context);
  }

  // Schedule every waiting task on the executor.
  auto waitingTask = queueHead.getTask();
  while (waitingTask) {
    // Find the next waiting task before we invalidate it by resuming
    // the task.
    auto nextWaitingTask = waitingTask->getNextWaitingTask();

    // Fill in the return context.
    auto waitingContext =
      static_cast<TaskFutureWaitAsyncContext *>(waitingTask->ResumeContext);
    if (hadErrorResult) {
      waitingContext->fillWithError(fragment);
    } else {
      waitingContext->fillWithSuccess(fragment);
    }

    _swift_tsan_acquire(static_cast<Job *>(waitingTask));

    // Enqueue the waiter on the global executor.
    // TODO: allow waiters to fill in a suggested executor
    swift_task_enqueueGlobal(waitingTask);

    // Move to the next task.
    waitingTask = nextWaitingTask;
  }
}

SWIFT_CC(swift)
static void destroyJob(SWIFT_CONTEXT HeapObject *obj) {
  assert(false && "A non-task job should never be destroyed as heap metadata.");
}

SWIFT_CC(swift)
static void destroyTask(SWIFT_CONTEXT HeapObject *obj) {
  auto task = static_cast<AsyncTask*>(obj);

  // For a future, destroy the result.
  if (task->isFuture()) {
    task->futureFragment()->destroy();
  }

  // Release any objects potentially held as task local values.
  task->Local.destroy(task);

  // The task execution itself should always hold a reference to it, so
  // if we get here, we know the task has finished running, which means
  // swift_task_complete should have been run, which will have torn down
  // the task-local allocator.  There's actually nothing else to clean up
  // here.

  free(task);
}

static void dummyVTableFunction(void) {
  abort();
}

FullMetadata<DispatchClassMetadata> swift::jobHeapMetadata = {
  {
    {
      &destroyJob
    },
    {
      /*value witness table*/ nullptr
    }
  },
  {
    MetadataKind::Job,
    dummyVTableFunction
  }
};

/// Heap metadata for an asynchronous task.
static FullMetadata<DispatchClassMetadata> taskHeapMetadata = {
  {
    {
      &destroyTask
    },
    {
      /*value witness table*/ nullptr
    }
  },
  {
    MetadataKind::Task,
    dummyVTableFunction
  }
};

const void *const swift::_swift_concurrency_debug_asyncTaskMetadata =
    static_cast<Metadata *>(&taskHeapMetadata);

/// The function that we put in the context of a simple task
/// to handle the final return.
SWIFT_CC(swiftasync)
static void completeTask(SWIFT_ASYNC_CONTEXT AsyncContext *context,
                         SWIFT_CONTEXT SwiftError *error) {
  // Set that there's no longer a running task in the current thread.
  auto task = _swift_task_clearCurrent();
  assert(task && "completing task, but there is no active task registered");

  // Store the error result.
  auto asyncContextPrefix = reinterpret_cast<AsyncContextPrefix *>(
      reinterpret_cast<char *>(context) - sizeof(AsyncContextPrefix));
  asyncContextPrefix->errorResult = error;

  // Destroy and deallocate any remaining task local items.
  // We need to do this before we destroy the task local deallocator.
  task->Local.destroy(task);

  // Tear down the task-local allocator immediately;
  // there's no need to wait for the object to be destroyed.
  _swift_task_alloc_destroy(task);

  // Complete the future.
  if (task->isFuture()) {
    task->completeFuture(context);
  }

  // TODO: set something in the status?
  // TODO: notify the parent somehow?
  // TODO: remove this task from the child-task chain?

  // Release the task, balancing the retain that a running task has on itself.
  // If it was a group child task, it will remain until the group returns it.
  swift_release(task);
}

/// The function that we put in the context of a simple task
/// to handle the final return from a closure.
SWIFT_CC(swiftasync)
static void completeTaskWithClosure(SWIFT_ASYNC_CONTEXT AsyncContext *context,
                                    SWIFT_CONTEXT SwiftError *error) {
  // Release the closure context.
  auto asyncContextPrefix = reinterpret_cast<AsyncContextPrefix *>(
      reinterpret_cast<char *>(context) - sizeof(AsyncContextPrefix));

  swift_release(asyncContextPrefix->closureContext);
  
  // Clean up the rest of the task.
  return completeTask(context, error);
}

SWIFT_CC(swiftasync)
static void non_future_adapter(SWIFT_ASYNC_CONTEXT AsyncContext *_context) {
  auto asyncContextPrefix = reinterpret_cast<AsyncContextPrefix *>(
      reinterpret_cast<char *>(_context) - sizeof(AsyncContextPrefix));
  return asyncContextPrefix->asyncEntryPoint(
      _context, asyncContextPrefix->closureContext);
}

SWIFT_CC(swiftasync)
static void future_adapter(SWIFT_ASYNC_CONTEXT AsyncContext *_context) {
  auto asyncContextPrefix = reinterpret_cast<FutureAsyncContextPrefix *>(
      reinterpret_cast<char *>(_context) - sizeof(FutureAsyncContextPrefix));
  return asyncContextPrefix->asyncEntryPoint(
      asyncContextPrefix->indirectResult, _context,
      asyncContextPrefix->closureContext);
}

SWIFT_CC(swiftasync)
static void task_wait_throwing_resume_adapter(SWIFT_ASYNC_CONTEXT AsyncContext *_context) {

  auto context = static_cast<TaskFutureWaitAsyncContext *>(_context);
  return context->asyncResumeEntryPoint(_context, context->errorResult);
}

/// All `swift_task_create*` variants funnel into this common implementation.
static AsyncTaskAndContext swift_task_create_group_future_impl(
    JobFlags flags, TaskGroup *group,
    const Metadata *futureResultType,
    FutureAsyncSignature::FunctionType *function,
    HeapObject * /* +1 */ closureContext,
    size_t initialContextSize) {
  assert((futureResultType != nullptr) == flags.task_isFuture());
  assert(!flags.task_isFuture() ||
         initialContextSize >= sizeof(FutureAsyncContext));
  assert((group != nullptr) == flags.task_isGroupChildTask());

  AsyncTask *parent = nullptr;
  if (flags.task_isChildTask()) {
    parent = swift_task_getCurrent();
    assert(parent != nullptr && "creating a child task with no active task");
  }

  // Figure out the size of the header.
  size_t headerSize = sizeof(AsyncTask);

  if (parent) {
    headerSize += sizeof(AsyncTask::ChildFragment);
  }

  if (flags.task_isGroupChildTask()) {
    headerSize += sizeof(AsyncTask::GroupChildFragment);
  }

  if (futureResultType) {
    headerSize += FutureFragment::fragmentSize(futureResultType);
    // Add the future async context prefix.
    headerSize += sizeof(FutureAsyncContextPrefix);
  } else {
    // Add the async context prefix.
    headerSize += sizeof(AsyncContextPrefix);
  }

  headerSize = llvm::alignTo(headerSize, llvm::Align(alignof(AsyncContext)));

  // Allocate the initial context together with the job.
  // This means that we never get rid of this allocation.
  size_t amountToAllocate = headerSize + initialContextSize;

  assert(amountToAllocate % MaximumAlignment == 0);

  void *allocation = malloc(amountToAllocate);

  AsyncContext *initialContext =
    reinterpret_cast<AsyncContext*>(
      reinterpret_cast<char*>(allocation) + headerSize);

  //  We can't just use `function` because it uses the new async function entry
  //  ABI -- passing parameters, closure context, indirect result addresses
  //  directly -- but AsyncTask->ResumeTask expects the signature to be
  //  `void (*, *, swiftasync *)`.
  //  Instead we use an adapter. This adaptor should use the storage prefixed to
  //  the async context to get at the parameters.
  //  See e.g. FutureAsyncContextPrefix.

  if (!futureResultType) {
    auto asyncContextPrefix = reinterpret_cast<AsyncContextPrefix *>(
        reinterpret_cast<char *>(allocation) + headerSize -
        sizeof(AsyncContextPrefix));
    asyncContextPrefix->asyncEntryPoint =
        reinterpret_cast<AsyncVoidClosureEntryPoint *>(function);
    asyncContextPrefix->closureContext = closureContext;
    function = non_future_adapter;
    assert(sizeof(AsyncContextPrefix) == 3 * sizeof(void *));
  } else {
    auto asyncContextPrefix = reinterpret_cast<FutureAsyncContextPrefix *>(
        reinterpret_cast<char *>(allocation) + headerSize -
        sizeof(FutureAsyncContextPrefix));
    asyncContextPrefix->asyncEntryPoint =
        reinterpret_cast<AsyncGenericClosureEntryPoint *>(function);
    function = future_adapter;
    asyncContextPrefix->closureContext = closureContext;
    assert(sizeof(FutureAsyncContextPrefix) == 4 * sizeof(void *));
  }

  // Initialize the task so that resuming it will run the given
  // function on the initial context.
  AsyncTask *task =
    new(allocation) AsyncTask(&taskHeapMetadata, flags,
                              function, initialContext);

  // Initialize the child fragment if applicable.
  if (parent) {
    auto childFragment = task->childFragment();
    new (childFragment) AsyncTask::ChildFragment(parent);
  }

  // Initialize the group child fragment if applicable.
  if (flags.task_isGroupChildTask()) {
    auto groupChildFragment = task->groupChildFragment();
    new (groupChildFragment) AsyncTask::GroupChildFragment(group);
  }
  
  // Initialize the future fragment if applicable.
  if (futureResultType) {
    assert(task->isFuture());
    auto futureFragment = task->futureFragment();
    new (futureFragment) FutureFragment(futureResultType);

    // Set up the context for the future so there is no error, and a successful
    // result will be written into the future fragment's storage.
    auto futureContext = static_cast<FutureAsyncContext *>(initialContext);
    auto futureAsyncContextPrefix =
        reinterpret_cast<FutureAsyncContextPrefix *>(
            reinterpret_cast<char *>(allocation) + headerSize -
            sizeof(FutureAsyncContextPrefix));
    futureAsyncContextPrefix->indirectResult = futureFragment->getStoragePtr();
  }
  

  // Perform additional linking between parent and child task.
  if (parent) {
    // If the parent was already cancelled, we carry this flag forward to the child.
    //
    // In a task group we would not have allowed the `add` to create a child anymore,
    // however better safe than sorry and `async let` are not expressed as task groups,
    // so they may have been spawned in any case still.
    if (swift_task_isCancelled(parent))
      swift_task_cancel(task);
  }

  // Configure the initial context.
  //
  // FIXME: if we store a null pointer here using the standard ABI for
  // signed null pointers, then we'll have to authenticate context pointers
  // as if they might be null, even though the only time they ever might
  // be is the final hop.  Store a signed null instead.
  initialContext->Parent = nullptr;
  initialContext->ResumeParent = reinterpret_cast<TaskContinuationFunction *>(
      closureContext ? &completeTaskWithClosure : &completeTask);
  initialContext->Flags = AsyncContextKind::Ordinary;
  initialContext->Flags.setShouldNotDeallocateInCallee(true);

  // Initialize the task-local allocator.
  // TODO: consider providing an initial pre-allocated first slab to the allocator.
  _swift_task_alloc_initialize(task);

  // TODO: if the allocator would be prepared earlier we could do this in some
  //       other existing if-parent if rather than adding another one here.
  if (parent) {
    // Initialize task locals with a link to the parent task.
    task->Local.initializeLinkParent(task, parent);
  }

  return {task, initialContext};
}

AsyncTaskAndContext
swift::swift_task_create_f(JobFlags flags,
                ThinNullaryAsyncSignature::FunctionType *function,
                           size_t initialContextSize) {
  return swift_task_create_future_f(
      flags, nullptr, function, initialContextSize);
}

AsyncTaskAndContext swift::swift_task_create_future_f(
    JobFlags flags,
    const Metadata *futureResultType,
    FutureAsyncSignature::FunctionType *function, size_t initialContextSize) {
  assert(!flags.task_isGroupChildTask() &&
  "use swift_task_create_group_future_f to initialize task group child tasks");
  return swift_task_create_group_future_f(
      flags, /*group=*/nullptr, futureResultType,
      function, initialContextSize);
}

AsyncTaskAndContext swift::swift_task_create_group_future_f(
    JobFlags flags, TaskGroup *group,
    const Metadata *futureResultType,
    FutureAsyncSignature::FunctionType *function,
    size_t initialContextSize) {
  return swift_task_create_group_future_impl(flags, group,
                                             futureResultType,
                                             function, nullptr,
                                             initialContextSize);
}

/// Extract the entry point address and initial context size from an async closure value.
template<typename AsyncSignature, uint16_t AuthDiscriminator>
SWIFT_ALWAYS_INLINE // so this doesn't hang out as a ptrauth gadget
std::pair<typename AsyncSignature::FunctionType *, size_t>
getAsyncClosureEntryPointAndContextSize(void *function,
                                        HeapObject *functionContext) {
  auto fnPtr =
      reinterpret_cast<const AsyncFunctionPointer<AsyncSignature> *>(function);
#if SWIFT_PTRAUTH
  fnPtr = (const AsyncFunctionPointer<AsyncSignature> *)ptrauth_auth_data(
      (void *)fnPtr, ptrauth_key_process_independent_code, AuthDiscriminator);
#endif
  return {reinterpret_cast<typename AsyncSignature::FunctionType *>(
              fnPtr->Function.get()),
          fnPtr->ExpectedContextSize};
}

AsyncTaskAndContext swift::swift_task_create_future(JobFlags flags,
                     const Metadata *futureResultType,
                     void *closureEntry,
                     HeapObject * /* +1 */ closureContext) {
  FutureAsyncSignature::FunctionType *taskEntry;
  size_t initialContextSize;
  std::tie(taskEntry, initialContextSize)
    = getAsyncClosureEntryPointAndContextSize<
      FutureAsyncSignature,
      SpecialPointerAuthDiscriminators::AsyncFutureFunction
    >(closureEntry, closureContext);

  return swift_task_create_group_future_impl(
      flags, nullptr, futureResultType,
      taskEntry, closureContext,
      initialContextSize);
}

AsyncTaskAndContext
swift::swift_task_create_group_future(
                        JobFlags flags, TaskGroup *group,
                        const Metadata *futureResultType,
                        void *closureEntry,
                        HeapObject * /*+1*/closureContext) {
  FutureAsyncSignature::FunctionType *taskEntry;
  size_t initialContextSize;
  std::tie(taskEntry, initialContextSize)
    = getAsyncClosureEntryPointAndContextSize<
      FutureAsyncSignature,
      SpecialPointerAuthDiscriminators::AsyncFutureFunction
    >(closureEntry, closureContext);
  return swift_task_create_group_future_impl(
      flags, group, futureResultType,
      taskEntry, closureContext,
      initialContextSize);
}

SWIFT_CC(swiftasync)
void swift::swift_task_future_wait(OpaqueValue *result,
                                   SWIFT_ASYNC_CONTEXT AsyncContext *rawContext,
                                   AsyncTask *task, Metadata *T) {
  // Suspend the waiting task.
  auto waitingTask = swift_task_getCurrent();
  waitingTask->ResumeTask = rawContext->ResumeParent;
  waitingTask->ResumeContext = rawContext;

  // Stash the result pointer for when we resume later.
  auto context = static_cast<TaskFutureWaitAsyncContext *>(rawContext);
  context->asyncResumeEntryPoint = nullptr;
  context->successResultPointer = result;
  context->errorResult = nullptr;


  // Wait on the future.
  assert(task->isFuture());

  switch (task->waitFuture(waitingTask)) {
  case FutureFragment::Status::Executing:
    // The waiting task has been queued on the future.
    return;

  case FutureFragment::Status::Success:
    // Run the task with a successful result.
    context->fillWithSuccess(task->futureFragment());
    // FIXME: force tail call
    return waitingTask->runInFullyEstablishedContext();

  case FutureFragment::Status::Error:
    fatalError(0, "future reported an error, but wait cannot throw");
  }
}

SWIFT_CC(swiftasync)
void swift::swift_task_future_wait_throwing(OpaqueValue *result,
    SWIFT_ASYNC_CONTEXT AsyncContext *rawContext, AsyncTask *task,
    Metadata *T) {
  auto waitingTask = swift_task_getCurrent();
  // Suspend the waiting task.
  auto originalResumeParent =
      reinterpret_cast<AsyncVoidClosureResumeEntryPoint *>(
          rawContext->ResumeParent);
  waitingTask->ResumeTask = task_wait_throwing_resume_adapter;
  waitingTask->ResumeContext = rawContext;

  // Stash the result pointer for when we resume later.
  auto context = static_cast<TaskFutureWaitAsyncContext *>(rawContext);
  context->successResultPointer = result;
  context->asyncResumeEntryPoint = originalResumeParent;
  context->errorResult = nullptr;

  // Wait on the future.
  assert(task->isFuture());

  switch (task->waitFuture(waitingTask)) {
  case FutureFragment::Status::Executing:
    // The waiting task has been queued on the future.
    return;

  case FutureFragment::Status::Success:
    // Run the task with a successful result.
    context->fillWithSuccess(task->futureFragment());
    // FIXME: force tail call
    return waitingTask->runInFullyEstablishedContext();

 case FutureFragment::Status::Error:
    // Run the task with an error result.
    context->fillWithError(task->futureFragment());
    // FIXME: force tail call
    return waitingTask->runInFullyEstablishedContext();
  }
}

namespace {

#if SWIFT_CONCURRENCY_COOPERATIVE_GLOBAL_EXECUTOR

class RunAndBlockSemaphore {
  bool Finished = false;
public:
  void wait() {
    donateThreadToGlobalExecutorUntil([](void *context) {
      return *reinterpret_cast<bool*>(context);
    }, &Finished);

    assert(Finished && "ran out of tasks before we were signalled");
  }

  void signal() {
    Finished = true;
  }
};

#else

class RunAndBlockSemaphore {
  ConditionVariable Queue;
  ConditionVariable::Mutex Lock;
  bool Finished = false;
public:
  /// Wait for a signal.
  void wait() {
    Lock.withLockOrWait(Queue, [&] {
      return Finished;
    });
  }

  void signal() {
    Lock.withLockThenNotifyAll(Queue, [&]{
      Finished = true;
    });
  }
};

#endif

using RunAndBlockSignature =
  AsyncSignature<void(HeapObject*), /*throws*/ false>;
struct RunAndBlockContext: AsyncContext {
  const void *Function;
  HeapObject *FunctionContext;
  RunAndBlockSemaphore *Semaphore;
};
using RunAndBlockCalleeContext =
  AsyncCalleeContext<RunAndBlockContext, RunAndBlockSignature>;

} // end anonymous namespace

/// Second half of the runAndBlock async function.
SWIFT_CC(swiftasync)
static void runAndBlock_finish(SWIFT_ASYNC_CONTEXT AsyncContext *_context) {
  auto calleeContext = static_cast<RunAndBlockCalleeContext*>(_context);

  auto context = popAsyncContext(calleeContext);

  context->Semaphore->signal();

  return context->ResumeParent(context);
}

/// First half of the runAndBlock async function.
SWIFT_CC(swiftasync)
static void runAndBlock_start(SWIFT_ASYNC_CONTEXT AsyncContext *_context,
                              SWIFT_CONTEXT HeapObject *closureContext) {
  auto callerContext = static_cast<RunAndBlockContext*>(_context);

  RunAndBlockSignature::FunctionType *function;
  size_t calleeContextSize;
  auto functionContext = callerContext->FunctionContext;
  assert(closureContext == functionContext);
  std::tie(function, calleeContextSize)
    = getAsyncClosureEntryPointAndContextSize<
      RunAndBlockSignature,
      SpecialPointerAuthDiscriminators::AsyncRunAndBlockFunction
    >(const_cast<void*>(callerContext->Function), functionContext);

  auto calleeContext =
    pushAsyncContext<RunAndBlockSignature>(callerContext,
                                           calleeContextSize,
                                           &runAndBlock_finish,
                                           functionContext);
  return reinterpret_cast<AsyncVoidClosureEntryPoint *>(function)(
      calleeContext, functionContext);
}

// TODO: Remove this hack.
void swift::swift_task_runAndBlockThread(const void *function,
                                         HeapObject *functionContext) {
  RunAndBlockSemaphore semaphore;

  // Set up a task that runs the runAndBlock async function above.
  auto flags = JobFlags(JobKind::Task, JobPriority::Default);
  auto pair = swift_task_create_f(
      flags,
      reinterpret_cast<ThinNullaryAsyncSignature::FunctionType *>(
          &runAndBlock_start),
      sizeof(RunAndBlockContext));
  auto context = static_cast<RunAndBlockContext*>(pair.InitialContext);
  context->Function = function;
  context->FunctionContext = functionContext;
  context->Semaphore = &semaphore;

  // Enqueue the task.
  swift_task_enqueueGlobal(pair.Task);

  // Wait until the task completes.
  semaphore.wait();
}

size_t swift::swift_task_getJobFlags(AsyncTask *task) {
  return task->Flags.getOpaqueValue();
}

namespace {
  
/// Structure that gets filled in when a task is suspended by `withUnsafeContinuation`.
struct AsyncContinuationContext {
  // These fields are unnecessary for resuming a continuation.
  void *Unused1;
  void *Unused2;
  // Storage slot for the error result, if any.
  SwiftError *ErrorResult;
  // Pointer to where to store a normal result.
  OpaqueValue *NormalResult;
  
  // Executor on which to resume execution.
  ExecutorRef ResumeExecutor;
};

static void resumeTaskAfterContinuation(AsyncTask *task,
                                        AsyncContinuationContext *context) {
  swift_task_enqueue(task, context->ResumeExecutor);
}

}

SWIFT_CC(swift)
void swift::swift_continuation_resume(/* +1 */ OpaqueValue *result,
                                      void *continuation,
                                      const Metadata *resumeType) {
  auto task = reinterpret_cast<AsyncTask*>(continuation);
  auto context = reinterpret_cast<AsyncContinuationContext*>(task->ResumeContext);
  resumeType->vw_initializeWithTake(context->NormalResult, result);
  
  resumeTaskAfterContinuation(task, context);
}

SWIFT_CC(swift)
void swift::swift_continuation_throwingResume(/* +1 */ OpaqueValue *result,
                                              void *continuation,
                                              const Metadata *resumeType) {
  return swift_continuation_resume(result, continuation, resumeType);
}


SWIFT_CC(swift)
void swift::swift_continuation_throwingResumeWithError(/* +1 */ SwiftError *error,
                                                       void *continuation,
                                                       const Metadata *resumeType) {
  auto task = reinterpret_cast<AsyncTask*>(continuation);
  auto context = reinterpret_cast<AsyncContinuationContext*>(task->ResumeContext);
  context->ErrorResult = error;
  
  resumeTaskAfterContinuation(task, context);
}

bool swift::swift_task_isCancelled(AsyncTask *task) {
  return task->isCancelled();
}

CancellationNotificationStatusRecord*
swift::swift_task_addCancellationHandler(
    CancellationNotificationStatusRecord::FunctionType handler) {
  void *allocation =
      swift_task_alloc(sizeof(CancellationNotificationStatusRecord));
  auto *record =
      new (allocation) CancellationNotificationStatusRecord(
          handler, /*arg=*/nullptr);

  swift_task_addStatusRecord(record);
  return record;
}

void swift::swift_task_removeCancellationHandler(
    CancellationNotificationStatusRecord *record) {
  swift_task_removeStatusRecord(record);
  swift_task_dealloc(record);
}

SWIFT_CC(swift)
void swift::swift_continuation_logFailedCheck(const char *message) {
  swift_reportError(0, message);
}

void swift::swift_task_asyncMainDrainQueue() {
#if SWIFT_CONCURRENCY_COOPERATIVE_GLOBAL_EXECUTOR
  bool Finished = false;
  donateThreadToGlobalExecutorUntil([](void *context) {
    return *reinterpret_cast<bool*>(context);
  }, &Finished);
#else
#if defined(_WIN32)
  static void(FAR *pfndispatch_main)(void) = NULL;

  if (pfndispatch_main)
    return pfndispatch_main();

  HMODULE hModule = LoadLibraryW(L"dispatch.dll");
  if (hModule == NULL)
    abort();

  pfndispatch_main =
      reinterpret_cast<void (FAR *)(void)>(GetProcAddress(hModule,
                                                          "dispatch_main"));
  if (pfndispatch_main == NULL)
    abort();

  pfndispatch_main();
  exit(0);
#else
  // CFRunLoop is not available on non-Darwin targets.  Foundation has an
  // implementation, but CoreFoundation is not meant to be exposed.  We can only
  // assume the existence of `CFRunLoopRun` on Darwin platforms, where the
  // system provides an implementation of CoreFoundation.
#if defined(__APPLE__)
  auto runLoop =
      reinterpret_cast<void (*)(void)>(dlsym(RTLD_DEFAULT, "CFRunLoopRun"));
  if (runLoop) {
    runLoop();
    exit(0);
  }
#endif

    dispatch_main();
#endif
#endif
}
