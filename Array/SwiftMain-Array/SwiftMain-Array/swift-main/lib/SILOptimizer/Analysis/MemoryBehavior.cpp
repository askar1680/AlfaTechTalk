//===--- MemoryBehavior.cpp -----------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#define DEBUG_TYPE "sil-membehavior"

#include "swift/SIL/InstructionUtils.h"
#include "swift/SIL/MemAccessUtils.h"
#include "swift/SIL/SILVisitor.h"
#include "swift/SILOptimizer/Analysis/AliasAnalysis.h"
#include "swift/SILOptimizer/Analysis/EscapeAnalysis.h"
#include "swift/SILOptimizer/Analysis/SideEffectAnalysis.h"
#include "swift/SILOptimizer/Analysis/ValueTracking.h"
#include "llvm/Support/Debug.h"

using namespace swift;

// The MemoryBehavior Cache must not grow beyond this size.
// We limit the size of the MB cache to 2**14 because we want to limit the
// memory usage of this cache.
static const int MemoryBehaviorAnalysisMaxCacheSize = 16384;

//===----------------------------------------------------------------------===//
//                       Memory Behavior Implementation
//===----------------------------------------------------------------------===//

namespace {

using MemBehavior = SILInstruction::MemoryBehavior;

/// Visitor that determines the memory behavior of an instruction relative to a
/// specific SILValue (i.e. can the instruction cause the value to be read,
/// etc.).
///
/// TODO: Clarify what it means to return a MayHaveSideEffects result. Does this
/// mean that the instruction may release objects referenced by value 'V'?
/// Deallocate the an address contained in 'V'? Are any other code motion
/// barriers relevant here?
class MemoryBehaviorVisitor
    : public SILInstructionVisitor<MemoryBehaviorVisitor, MemBehavior> {

  AliasAnalysis *AA;

  SideEffectAnalysis *SEA;

  EscapeAnalysis *EA;

  /// The value we are attempting to discover memory behavior relative to.
  SILValue V;

  /// Cache either the address of the access corresponding to memory at 'V', or
  /// 'V' itself if it isn't recognized as part of an access. The cached value
  /// is always a valid SILValue.
  SILValue cachedValueAddress;

  Optional<bool> cachedIsLetValue;

  /// The SILType of the value.
  Optional<SILType> TypedAccessTy;

public:
  MemoryBehaviorVisitor(AliasAnalysis *AA, SideEffectAnalysis *SEA,
                        EscapeAnalysis *EA, SILValue V)
      : AA(AA), SEA(SEA), EA(EA), V(V) {}

  SILType getValueTBAAType() {
    if (!TypedAccessTy)
      TypedAccessTy = computeTBAAType(V);
    return *TypedAccessTy;
  }

  /// If 'V' is an address projection within a formal access, return the
  /// canonical address of the formal access if possible without looking past
  /// any storage casts. Otherwise, a "best-effort" address
  ///
  /// If 'V' is an address, then the returned value is also an address.
  SILValue getValueAddress() {
    if (!cachedValueAddress) {
      cachedValueAddress =
          V->getType().isAddress() ? getTypedAccessAddress(V) : V;
    }
    return cachedValueAddress;
  }

  /// Return true if 'V's accessed address is that of a let variables.
  bool isLetValue() {
    if (!cachedIsLetValue) {
      cachedIsLetValue =
          V->getType().isAddress() && isLetAddress(getValueAddress());
    }
    return cachedIsLetValue.getValue();
  }

  // Return true is the given address (or pointer) may alias with 'V'.
  bool mayAlias(SILValue opAddress) {
    if (AA->isNoAlias(opAddress, V, computeTBAAType(opAddress),
                      getValueTBAAType())) {
      LLVM_DEBUG(llvm::dbgs()
                 << "No alias: access " << opAddress << " value " << V);
      return false;
    }
    LLVM_DEBUG(llvm::dbgs()
               << "May alias: access " << opAddress << " value " << V);
    return true;
  }

  MemBehavior visitValueBase(ValueBase *V) {
    llvm_unreachable("unimplemented");
  }

  MemBehavior visitSILInstruction(SILInstruction *Inst) {
    // If we do not have any more information, just use the general memory
    // behavior implementation.
    auto Behavior = Inst->getMemoryBehavior();

    // If this is a regular read-write access then return the computed memory
    // behavior.
    if (!isLetValue())
      return Behavior;

    // If this is a read-only access to 'let variable'. Other side effects, such
    // as releases of the object containing a 'let' property are still relevant.
    switch (Behavior) {
    case MemBehavior::MayReadWrite:       return MemBehavior::MayRead;
    case MemBehavior::MayWrite:           return MemBehavior::None;
    default: return Behavior;
    }
  }

  MemBehavior visitBeginAccessInst(BeginAccessInst *beginAccess) {
    switch (beginAccess->getAccessKind()) {
    case SILAccessKind::Deinit:
      // A [deinit] only directly reads from the object. The fact that it frees
      // memory is modeled more precisely by the release operations within the
      // deinit scope. Therefore, handle it like a [read] here...
      LLVM_FALLTHROUGH;
    case SILAccessKind::Read:
      if (!mayAlias(beginAccess->getSource()))
        return MemBehavior::None;

      return MemBehavior::MayRead;

    case SILAccessKind::Modify:
      if (isLetValue()) {
        assert(getAccessBase(beginAccess) != getValueAddress()
               && "let modification not allowed");
        return MemBehavior::None;
      }
      // [modify] has a special case for ignoring 'let's, but otherwise is
      // identical to an [init]...
      LLVM_FALLTHROUGH;
    case SILAccessKind::Init:
      if (!mayAlias(beginAccess->getSource()))
        return MemBehavior::None;

      return MemBehavior::MayWrite;
    }
    llvm_unreachable("invalid access kind");
  }

  MemBehavior visitEndAccessInst(EndAccessInst *endAccess) {
    return visitBeginAccessInst(endAccess->getBeginAccess());
  }

  MemBehavior visitLoadInst(LoadInst *LI);
  MemBehavior visitStoreInst(StoreInst *SI);
  MemBehavior visitCopyAddrInst(CopyAddrInst *CAI);
  MemBehavior visitApplyInst(ApplyInst *AI);
  MemBehavior visitTryApplyInst(TryApplyInst *AI);
  MemBehavior visitBeginApplyInst(BeginApplyInst *AI);
  MemBehavior visitEndApplyInst(EndApplyInst *EAI);
  MemBehavior visitAbortApplyInst(AbortApplyInst *AAI);
  MemBehavior getApplyBehavior(FullApplySite AS);
  MemBehavior visitBuiltinInst(BuiltinInst *BI);
  MemBehavior visitStrongReleaseInst(StrongReleaseInst *BI);
  MemBehavior visitReleaseValueInst(ReleaseValueInst *BI);
  MemBehavior visitDestroyValueInst(DestroyValueInst *DVI);
  MemBehavior visitSetDeallocatingInst(SetDeallocatingInst *BI);
  MemBehavior visitBeginCOWMutationInst(BeginCOWMutationInst *BCMI);
#define ALWAYS_OR_SOMETIMES_LOADABLE_CHECKED_REF_STORAGE(Name, ...) \
  MemBehavior visit##Name##ReleaseInst(Name##ReleaseInst *BI);
#include "swift/AST/ReferenceStorage.def"

  // Instructions which are none if our SILValue does not alias one of its
  // arguments. If we cannot prove such a thing, return the relevant memory
  // behavior.
#define OPERANDALIAS_MEMBEHAVIOR_INST(Name)                                    \
  MemBehavior visit##Name(Name *I) {                                           \
    for (Operand & Op : I->getAllOperands()) {                                 \
      if (mayAlias(Op.get()))                                                  \
        return I->getMemoryBehavior();                                         \
    }                                                                          \
    return MemBehavior::None;                                                  \
  }

  OPERANDALIAS_MEMBEHAVIOR_INST(InjectEnumAddrInst)
  OPERANDALIAS_MEMBEHAVIOR_INST(UncheckedTakeEnumDataAddrInst)
  OPERANDALIAS_MEMBEHAVIOR_INST(InitExistentialAddrInst)
  OPERANDALIAS_MEMBEHAVIOR_INST(DeinitExistentialAddrInst)
  OPERANDALIAS_MEMBEHAVIOR_INST(DeallocStackInst)
  OPERANDALIAS_MEMBEHAVIOR_INST(FixLifetimeInst)
  OPERANDALIAS_MEMBEHAVIOR_INST(ClassifyBridgeObjectInst)
  OPERANDALIAS_MEMBEHAVIOR_INST(ValueToBridgeObjectInst)
#undef OPERANDALIAS_MEMBEHAVIOR_INST

  // Override simple behaviors where MayHaveSideEffects is too general and
  // encompasses other behavior that is not read/write/ref count decrement
  // behavior we care about.
#define SIMPLE_MEMBEHAVIOR_INST(Name, Behavior)                         \
  MemBehavior visit##Name(Name *I) { return MemBehavior::Behavior; }
  SIMPLE_MEMBEHAVIOR_INST(CondFailInst, None)
#undef SIMPLE_MEMBEHAVIOR_INST

  // Incrementing reference counts doesn't have an observable memory effect.
#define REFCOUNTINC_MEMBEHAVIOR_INST(Name)                                     \
  MemBehavior visit##Name(Name *I) {                                           \
    return MemBehavior::None;                                                \
  }
  REFCOUNTINC_MEMBEHAVIOR_INST(StrongRetainInst)
  REFCOUNTINC_MEMBEHAVIOR_INST(RetainValueInst)
  REFCOUNTINC_MEMBEHAVIOR_INST(CopyValueInst)
#define UNCHECKED_REF_STORAGE(Name, ...)                                       \
  REFCOUNTINC_MEMBEHAVIOR_INST(Name##RetainValueInst)                          \
  REFCOUNTINC_MEMBEHAVIOR_INST(StrongCopy##Name##ValueInst)
#define ALWAYS_OR_SOMETIMES_LOADABLE_CHECKED_REF_STORAGE(Name, ...)            \
  REFCOUNTINC_MEMBEHAVIOR_INST(Name##RetainInst)                               \
  REFCOUNTINC_MEMBEHAVIOR_INST(StrongRetain##Name##Inst)                       \
  REFCOUNTINC_MEMBEHAVIOR_INST(StrongCopy##Name##ValueInst)
#include "swift/AST/ReferenceStorage.def"
#undef REFCOUNTINC_MEMBEHAVIOR_INST
};

} // end anonymous namespace

MemBehavior MemoryBehaviorVisitor::visitLoadInst(LoadInst *LI) {
  if (!mayAlias(LI->getOperand()))
    return MemBehavior::None;

  LLVM_DEBUG(llvm::dbgs() << "  Could not prove that load inst does not alias "
                             "pointer. ");

  if (LI->getOwnershipQualifier() == LoadOwnershipQualifier::Take) {
    LLVM_DEBUG(llvm::dbgs() << "Is a take so return MayReadWrite.\n");
    return MemBehavior::MayReadWrite;
  }

  LLVM_DEBUG(llvm::dbgs() << "Not a take so returning MayRead.\n");
  return MemBehavior::MayRead;
}

MemBehavior MemoryBehaviorVisitor::visitStoreInst(StoreInst *SI) {
  // No store besides the initialization of a "let"-variable
  // can have any effect on the value of this "let" variable.
  if (isLetValue() && (getAccessBase(SI->getDest()) != getValueAddress())) {
    return MemBehavior::None;
  }
  // If the store dest cannot alias the pointer in question and we are not
  // releasing anything due to an assign, then the specified value cannot be
  // modified by the store.
  if (!mayAlias(SI->getDest()) &&
      SI->getOwnershipQualifier() != StoreOwnershipQualifier::Assign)
    return MemBehavior::None;

  // Otherwise, a store just writes.
  LLVM_DEBUG(llvm::dbgs() << "  Could not prove store does not alias inst. "
                             "Returning default mem behavior.\n");
  return SI->getMemoryBehavior();
}

MemBehavior MemoryBehaviorVisitor::visitCopyAddrInst(CopyAddrInst *CAI) {
  // If it's an assign to the destination, a destructor might be called on the
  // old value. This can have any side effects.
  // We could also check if it's a trivial type (which cannot have any side
  // effect on destruction), but such copy_addr instructions are optimized to
  // load/stores anyway, so it's probably not worth it.
  if (!CAI->isInitializationOfDest())
    return MemBehavior::MayHaveSideEffects;

  bool mayWrite = mayAlias(CAI->getDest());
  bool mayRead = mayAlias(CAI->getSrc());
  
  if (mayRead) {
    if (mayWrite)
      return MemBehavior::MayReadWrite;

    // A take is modelled as a write. See MemoryBehavior::MayWrite.
    if (CAI->isTakeOfSrc())
      return MemBehavior::MayReadWrite;

    return MemBehavior::MayRead;
  }
  if (mayWrite)
    return MemBehavior::MayWrite;

  return MemBehavior::None;
}

MemBehavior MemoryBehaviorVisitor::visitBuiltinInst(BuiltinInst *BI) {
  // If our callee is not a builtin, be conservative and return may have side
  // effects.
  if (!BI) {
    return MemBehavior::MayHaveSideEffects;
  }

  // If the builtin is read none, it does not read or write memory.
  if (!BI->mayReadOrWriteMemory()) {
    LLVM_DEBUG(llvm::dbgs() << "  Found apply of read none builtin. Returning"
                               " None.\n");
    return MemBehavior::None;
  }

  // If the builtin is side effect free, then it can only read memory.
  if (!BI->mayHaveSideEffects()) {
    LLVM_DEBUG(llvm::dbgs() << "  Found apply of side effect free builtin. "
                               "Returning MayRead.\n");
    return MemBehavior::MayRead;
  }

  // FIXME: If the value (or any other values from the instruction that the
  // value comes from) that we are tracking does not escape and we don't alias
  // any of the arguments of the apply inst, we should be ok.

  // Otherwise be conservative and return that we may have side effects.
  LLVM_DEBUG(llvm::dbgs() << "  Found apply of side effect builtin. "
                             "Returning MayHaveSideEffects.\n");
  return MemBehavior::MayHaveSideEffects;
}

MemBehavior MemoryBehaviorVisitor::visitTryApplyInst(TryApplyInst *AI) {
  return getApplyBehavior(AI);
}

MemBehavior MemoryBehaviorVisitor::visitApplyInst(ApplyInst *AI) {
  return getApplyBehavior(AI);
}

MemBehavior MemoryBehaviorVisitor::visitBeginApplyInst(BeginApplyInst *AI) {
  return getApplyBehavior(AI);
}

MemBehavior MemoryBehaviorVisitor::visitEndApplyInst(EndApplyInst *EAI) {
  return getApplyBehavior(EAI->getBeginApply());
}

MemBehavior MemoryBehaviorVisitor::visitAbortApplyInst(AbortApplyInst *AAI) {
  return getApplyBehavior(AAI->getBeginApply());
}

/// Returns true if the \p address may have any users which let the address
/// escape in an unusual way, e.g. with an address_to_pointer instruction.
static bool hasEscapingUses(SILValue address, int &numChecks) {
  for (Operand *use : address->getUses()) {
    SILInstruction *user = use->getUser();
    
    // Avoid quadratic complexity in corner cases. A limit of 24 is more than
    // enough in most cases.
    if (++numChecks > 24)
      return true;

    switch (user->getKind()) {
      case SILInstructionKind::DebugValueAddrInst:
      case SILInstructionKind::FixLifetimeInst:
      case SILInstructionKind::LoadInst:
      case SILInstructionKind::StoreInst:
      case SILInstructionKind::CopyAddrInst:
      case SILInstructionKind::DestroyAddrInst:
      case SILInstructionKind::DeallocStackInst:
      case SILInstructionKind::EndAccessInst:
        // Those instructions have no result and cannot escape the address.
        break;
      case SILInstructionKind::ApplyInst:
      case SILInstructionKind::TryApplyInst:
      case SILInstructionKind::BeginApplyInst:
        // Apply instructions can not let an address escape either. It's not
        // possible that an address, passed as an indirect parameter, escapes
        // the function in any way (which is not unsafe and undefined behavior).
        break;
      case SILInstructionKind::BeginAccessInst:
      case SILInstructionKind::OpenExistentialAddrInst:
      case SILInstructionKind::UncheckedTakeEnumDataAddrInst:
      case SILInstructionKind::StructElementAddrInst:
      case SILInstructionKind::TupleElementAddrInst:
      case SILInstructionKind::UncheckedAddrCastInst:
        // Check the uses of address projections.
        if (hasEscapingUses(cast<SingleValueInstruction>(user), numChecks))
          return true;
        break;
      case SILInstructionKind::AddressToPointerInst:
        // This is _the_ instruction which can let an address escape.
        return true;
      default:
        // To be conservative, also bail for anything we don't handle here.
        return true;
    }
  }
  return false;
}

MemBehavior MemoryBehaviorVisitor::getApplyBehavior(FullApplySite AS) {

  // Do a quick check first: if V is directly passed to an in_guaranteed
  // argument, we know that the function cannot write to it.
  for (Operand &argOp : AS.getArgumentOperands()) {
    if (argOp.get() == V &&
        AS.getArgumentConvention(argOp) ==
          swift::SILArgumentConvention::Indirect_In_Guaranteed) {
      return MemBehavior::MayRead;
    }
  }

  SILValue object = getUnderlyingObject(V);
  int numUsesChecked = 0;
  
  // For exclusive/local addresses we can do a quick and good check with alias
  // analysis. For everything else we use escape analysis (see below).
  // TODO: The check for not-escaping can probably done easier with the upcoming
  // API of AccessStorage.
  bool nonEscapingAddress =
    (isa<AllocStackInst>(object) || isExclusiveArgument(object)) &&
    !hasEscapingUses(object, numUsesChecked);

  FunctionSideEffects applyEffects;
  SEA->getCalleeEffects(applyEffects, AS);

  MemBehavior behavior = MemBehavior::None;
  MemBehavior globalBehavior = applyEffects.getGlobalEffects().getMemBehavior(
                           RetainObserveKind::IgnoreRetains);

  // If it's a non-escaping address, we don't care about the "global" effects
  // of the called function.
  if (!nonEscapingAddress)
    behavior = globalBehavior;
  
  // Check all parameter effects.
  for (unsigned argIdx = 0, end = AS.getNumArguments();
       argIdx < end && behavior < MemBehavior::MayHaveSideEffects;
       ++argIdx) {
    SILValue arg = AS.getArgument(argIdx);
    
    // In case the argument is not an address, alias analysis will always report
    // a no-alias. Therefore we have to treat non-address arguments
    // conservatively here. For example V could be a ref_element_addr of a
    // reference argument. In this case V clearly "aliases" the argument, but
    // this is not reported by alias analysis.
    if ((!nonEscapingAddress && !arg->getType().isAddress()) ||
         mayAlias(arg)) {
      MemBehavior argBehavior = applyEffects.getArgumentBehavior(AS, argIdx);
      behavior = combineMemoryBehavior(behavior, argBehavior);
    }
  }

  if (behavior > MemBehavior::None) {
    if (behavior > MemBehavior::MayRead && isLetValue())
      behavior = MemBehavior::MayRead;

    // Ask escape analysis.
    if (!EA->canEscapeTo(V, AS))
      behavior = MemBehavior::None;
  }
  LLVM_DEBUG(llvm::dbgs() << "  Found apply, returning " << behavior << '\n');

  return behavior;
}

MemBehavior
MemoryBehaviorVisitor::visitStrongReleaseInst(StrongReleaseInst *SI) {
  if (!EA->canEscapeTo(V, SI))
    return MemBehavior::None;
  return MemBehavior::MayHaveSideEffects;
}

#define ALWAYS_OR_SOMETIMES_LOADABLE_CHECKED_REF_STORAGE(Name, ...) \
MemBehavior \
MemoryBehaviorVisitor::visit##Name##ReleaseInst(Name##ReleaseInst *SI) { \
  if (!EA->canEscapeTo(V, SI)) \
    return MemBehavior::None; \
  return MemBehavior::MayHaveSideEffects; \
}
#include "swift/AST/ReferenceStorage.def"

MemBehavior MemoryBehaviorVisitor::visitReleaseValueInst(ReleaseValueInst *SI) {
  if (!EA->canEscapeTo(V, SI))
    return MemBehavior::None;
  return MemBehavior::MayHaveSideEffects;
}

MemBehavior
MemoryBehaviorVisitor::visitDestroyValueInst(DestroyValueInst *DVI) {
  if (!EA->canEscapeTo(V, DVI))
    return MemBehavior::None;
  return MemBehavior::MayHaveSideEffects;
}

MemBehavior MemoryBehaviorVisitor::visitSetDeallocatingInst(SetDeallocatingInst *SDI) {
  return MemBehavior::None;
}

MemBehavior MemoryBehaviorVisitor::
visitBeginCOWMutationInst(BeginCOWMutationInst *BCMI) {
  // begin_cow_mutation is defined to have side effects, because it has
  // dependencies with instructions which retain the buffer operand.
  // But it never interferes with any memory address.
  return MemBehavior::None;
}

//===----------------------------------------------------------------------===//
//                            Top Level Entrypoint
//===----------------------------------------------------------------------===//

MemBehavior
AliasAnalysis::computeMemoryBehavior(SILInstruction *Inst, SILValue V) {
  MemBehaviorKeyTy Key = toMemoryBehaviorKey(Inst, V);
  // Check if we've already computed this result.
  auto It = MemoryBehaviorCache.find(Key);
  if (It != MemoryBehaviorCache.end()) {
    return It->second;
  }

  // Flush the cache if the size of the cache is too large.
  if (MemoryBehaviorCache.size() > MemoryBehaviorAnalysisMaxCacheSize) {
    MemoryBehaviorCache.clear();
  }

  // Calculate the aliasing result and store it in the cache.
  auto Result = computeMemoryBehaviorInner(Inst, V);
  MemoryBehaviorCache[Key] = Result;
  return Result;
}

MemBehavior
AliasAnalysis::computeMemoryBehaviorInner(SILInstruction *Inst, SILValue V) {
  LLVM_DEBUG(llvm::dbgs() << "GET MEMORY BEHAVIOR FOR:\n    " << *Inst << "    "
                          << *V);
  assert(SEA && "SideEffectsAnalysis must be initialized!");
  return MemoryBehaviorVisitor(this, SEA, EA, V).visit(Inst);
}

MemBehaviorKeyTy AliasAnalysis::toMemoryBehaviorKey(SILInstruction *V1,
                                                    SILValue V2) {
  size_t idx1 = InstructionToIndex.getIndex(V1);
  assert(idx1 != std::numeric_limits<size_t>::max() &&
         "~0 index reserved for empty/tombstone keys");
  size_t idx2 = ValueToIndex.getIndex(V2);
  assert(idx2 != std::numeric_limits<size_t>::max() &&
         "~0 index reserved for empty/tombstone keys");
  return {idx1, idx2};
}
