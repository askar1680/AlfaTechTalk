// RUN: %empty-directory(%t)
// RUN: %target-build-swift -Xfrontend -enable-experimental-concurrency -g %s -module-name main -o %t/main
// RUN: %target-codesign %t/main
// RUN: %target-run %t/main | %FileCheck %s

// REQUIRES: executable_test
// REQUIRES: concurrency
// UNSUPPORTED: use_os_stdlib
// XFAIL: OS=windows-msvc

struct E : Error {}

func asyncCanThrowDoesThrow() async throws -> Int {
  throw E()
}

func asyncCanThrowDoesntThrow() async throws -> Int {
  return 0
}

func syncCanThrowDoesThrow() throws -> Int {
  throw E()
}

func syncCanThrowDoesntThrow() throws -> Int {
  return 0
}

func asyncCanThrowDoesThrowRecursive(_ index: Int) async throws -> Int {
  if index > 0 {
    return try await asyncCanThrowDoesThrowRecursive(index - 1)
  } else {
    return try await asyncCanThrowDoesThrow()
  }
}

func asyncCanThrowDoesntThrowRecursive(_ index: Int) async throws -> Int {
  if index > 0 {
    return try await asyncCanThrowDoesntThrowRecursive(index - 1)
  } else {
    return try await asyncCanThrowDoesntThrow()
  }
}

func syncCanThrowDoesThrowRecursive(_ index: Int) async throws -> Int {
  if index > 0 {
    return try await syncCanThrowDoesThrowRecursive(index - 1)
  } else {
    return try syncCanThrowDoesThrow()
  }
}

func syncCanThrowDoesntThrowRecursive(_ index: Int) async throws -> Int {
  if index > 0 {
    return try await syncCanThrowDoesntThrowRecursive(index - 1)
  } else {
    return try syncCanThrowDoesntThrow()
  }
}

func test<T>(_ work: () async throws -> T) async {
  do {
    let value = try await work()
    print(value)
  }
  catch let error {
    print(error)
  }
}

// CHECK: E()
// CHECK: 0
// CHECK: E()
// CHECK: 0
func testRecursion() async {
  await test { try await asyncCanThrowDoesThrowRecursive(10) }
  await test { try await asyncCanThrowDoesntThrowRecursive(10) }
  await test { try await syncCanThrowDoesThrowRecursive(10) }
  await test { try await syncCanThrowDoesntThrowRecursive(10) }
}

func testAsyncDoesThrowThenSyncDoesThrow() async throws -> (Int, Int) {
  let async = try await asyncCanThrowDoesThrow()
  let sync = try syncCanThrowDoesThrow()
  return (async, sync)
}

func testAsyncDoesThrowThenSyncDoesntThrow() async throws -> (Int, Int) {
  let async = try await asyncCanThrowDoesThrow()
  let sync = try syncCanThrowDoesntThrow()
  return (async, sync)
}

func testAsyncDoesntThrowThenSyncDoesThrow() async throws -> (Int, Int) {
  let async = try await asyncCanThrowDoesntThrow()
  let sync = try syncCanThrowDoesThrow()
  return (async, sync)
}

func testAsyncDoesntThrowThenSyncDoesntThrow() async throws -> (Int, Int) {
  let async = try await asyncCanThrowDoesntThrow()
  let sync = try syncCanThrowDoesntThrow()
  return (async, sync)
}


func testSyncDoesThrowThenAsyncDoesThrow() async throws -> (Int, Int) {
  let sync = try syncCanThrowDoesThrow()
  let async = try await asyncCanThrowDoesThrow()
  return (sync, async)
}

func testSyncDoesThrowThenAsyncDoesntThrow() async throws -> (Int, Int) {
  let sync = try syncCanThrowDoesThrow()
  let async = try await asyncCanThrowDoesntThrow()
  return (sync, async)
}

func testSyncDoesntThrowThenAsyncDoesThrow() async throws -> (Int, Int) {
  let sync = try syncCanThrowDoesntThrow()
  let async = try await asyncCanThrowDoesThrow()
  return (sync, async)
}

func testSyncDoesntThrowThenAsyncDoesntThrow() async throws -> (Int, Int) {
  let sync = try syncCanThrowDoesntThrow()
  let async = try await asyncCanThrowDoesntThrow()
  return (sync, async)
}

// CHECK: E()
// CHECK: E()
// CHECK: E()
// CHECK: (0, 0)
// CHECK: E()
// CHECK: E()
// CHECK: E()
// CHECK: (0, 0)
func testMixture() async {
  await test { try await testAsyncDoesThrowThenSyncDoesThrow() }
  await test { try await testAsyncDoesThrowThenSyncDoesntThrow() }
  await test { try await testAsyncDoesntThrowThenSyncDoesThrow() }
  await test { try await testAsyncDoesntThrowThenSyncDoesntThrow() }

  await test { try await testSyncDoesThrowThenAsyncDoesThrow() }
  await test { try await testSyncDoesThrowThenAsyncDoesntThrow() }
  await test { try await testSyncDoesntThrowThenAsyncDoesThrow() }
  await test { try await testSyncDoesntThrowThenAsyncDoesntThrow() }
}

runAsyncAndBlock {
  await testRecursion()
  await testMixture()
}
