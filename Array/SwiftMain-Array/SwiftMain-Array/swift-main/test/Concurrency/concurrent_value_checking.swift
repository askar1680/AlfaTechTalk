// RUN: %target-typecheck-verify-swift -enable-experimental-concurrency -warn-concurrency
// REQUIRES: concurrency

class NotConcurrent { }

// ----------------------------------------------------------------------
// Sendable restriction on actor operations
// ----------------------------------------------------------------------

actor A1 {
  let localLet: NotConcurrent = NotConcurrent()
  func synchronous() -> NotConcurrent? { nil }
  func asynchronous(_: NotConcurrent?) async { }
}

actor A2 {
  var localVar: NotConcurrent

  init(value: NotConcurrent) {
    self.localVar = value
  }
}

func testActorCreation(value: NotConcurrent) {
  _ = A2(value: value) // expected-warning{{cannot pass argument of non-sendable type 'NotConcurrent' across actors}}
}

extension A1 {
  func testIsolation(other: A1) async {
    // All within the same actor domain, so the Sendable restriction
    // does not apply.
    _ = localLet
    _ = synchronous()
    _ = await asynchronous(nil)
    _ = self.localLet
    _ = self.synchronous()
    _ = await self.asynchronous(nil)

    // Across to a different actor, so Sendable restriction is enforced.
    _ = other.localLet // expected-warning{{cannot use property 'localLet' with a non-sendable type 'NotConcurrent' across actors}}
    _ = await other.synchronous() // expected-warning{{cannot call function returning non-sendable type 'NotConcurrent?' across actors}}
    _ = await other.asynchronous(nil) // expected-warning{{cannot pass argument of non-sendable type 'NotConcurrent?' across actors}}
  }
}

// ----------------------------------------------------------------------
// Sendable restriction on global actor operations
// ----------------------------------------------------------------------
actor TestActor {}

@globalActor
struct SomeGlobalActor {
  static var shared: TestActor { TestActor() }
}

@SomeGlobalActor
let globalValue: NotConcurrent? = nil

@SomeGlobalActor
func globalSync(_: NotConcurrent?) {
}

@SomeGlobalActor
func globalAsync(_: NotConcurrent?) async {
  await globalAsync(globalValue) // both okay because we're in the actor
  globalSync(nil)
}

func globalTest() async {
  let a = globalValue // expected-warning{{cannot use let 'globalValue' with a non-sendable type 'NotConcurrent?' across actors}}
  await globalAsync(a) // expected-warning{{cannot pass argument of non-sendable type 'NotConcurrent?' across actors}}
  await globalSync(a)  // expected-warning{{cannot pass argument of non-sendable type 'NotConcurrent?' across actors}}
}

struct HasSubscript {
  @SomeGlobalActor
  subscript (i: Int) -> NotConcurrent? { nil }
}

class ClassWithGlobalActorInits {
  @SomeGlobalActor
  init(_: NotConcurrent) { }

  @SomeGlobalActor
  init() { }
}


@MainActor
func globalTestMain(nc: NotConcurrent) async {
  let a = globalValue // expected-warning{{cannot use let 'globalValue' with a non-sendable type 'NotConcurrent?' across actors}}
  await globalAsync(a) // expected-warning{{cannot pass argument of non-sendable type 'NotConcurrent?' across actors}}
  await globalSync(a)  // expected-warning{{cannot pass argument of non-sendable type 'NotConcurrent?' across actors}}
  _ = await ClassWithGlobalActorInits(nc) // expected-warning{{cannot pass argument of non-sendable type 'NotConcurrent' across actors}}
  _ = await ClassWithGlobalActorInits()
}

@SomeGlobalActor
func someGlobalTest(nc: NotConcurrent) {
  let hs = HasSubscript()
  let _ = hs[0] // okay
  _ = ClassWithGlobalActorInits(nc)
}

// ----------------------------------------------------------------------
// Sendable restriction on captures.
// ----------------------------------------------------------------------
func acceptNonConcurrent(_: () -> Void) { }
func acceptConcurrent(_: @Sendable () -> Void) { }

func testConcurrency() {
  let x = NotConcurrent()
  var y = NotConcurrent()
  y = NotConcurrent()
  acceptNonConcurrent {
    print(x) // okay
    print(y) // okay
  }
  acceptConcurrent {
    print(x) // expected-warning{{cannot use let 'x' with a non-sendable type 'NotConcurrent' from concurrently-executed code}}
    print(y) // expected-error{{reference to captured var 'y' in concurrently-executing code}}
  }
}

// ----------------------------------------------------------------------
// Sendable restriction on key paths.
// ----------------------------------------------------------------------
class NC: Hashable {
  func hash(into: inout Hasher) { }
  static func==(_: NC, _: NC) -> Bool { true }
}

class HasNC {
  var dict: [NC: Int] = [:]
}

func testKeyPaths(dict: [NC: Int], nc: NC) {
  _ = \HasNC.dict[nc] // expected-warning{{cannot form key path that captures non-sendable type 'NC'}}
}


// ----------------------------------------------------------------------
// Sendable restriction on conformances.
// ----------------------------------------------------------------------
protocol AsyncProto {
  func asyncMethod(_: NotConcurrent) async
}

extension A1: AsyncProto {
  // FIXME: Poor diagnostic.
  func asyncMethod(_: NotConcurrent) async { } // expected-warning{{cannot pass argument of non-sendable type 'NotConcurrent' across actors}}
}

protocol MainActorProto {
  func asyncMainMethod(_: NotConcurrent) async
}

class SomeClass: MainActorProto {
  @SomeGlobalActor
  func asyncMainMethod(_: NotConcurrent) async { } // expected-warning{{cannot pass argument of non-sendable type 'NotConcurrent' across actors}}
}

// ----------------------------------------------------------------------
// Sendable restriction on concurrent functions.
// ----------------------------------------------------------------------

@Sendable func concurrentFunc() -> NotConcurrent? { nil }

// ----------------------------------------------------------------------
// No Sendable restriction on @Sendable function types.
// ----------------------------------------------------------------------
typealias CF = @Sendable () -> NotConcurrent?
typealias BadGenericCF<T> = @Sendable () -> T?
typealias GoodGenericCF<T: Sendable> = @Sendable () -> T? // okay

var concurrentFuncVar: (@Sendable (NotConcurrent) -> Void)? = nil

// ----------------------------------------------------------------------
// Sendable restriction on @Sendable closures.
// ----------------------------------------------------------------------
func acceptConcurrentUnary<T>(_: @Sendable (T) -> T) { }

func concurrentClosures<T>(_: T) {
  acceptConcurrentUnary { (x: T) in
    _ = x // ok
    acceptConcurrentUnary { _ in x } // expected-warning{{cannot use parameter 'x' with a non-sendable type 'T' from concurrently-executed code}}
  }
}

// ----------------------------------------------------------------------
// Sendable checking
// ----------------------------------------------------------------------
struct S1: Sendable {
  var nc: NotConcurrent // expected-error{{stored property 'nc' of 'Sendable'-conforming struct 'S1' has non-sendable type 'NotConcurrent'}}
}

struct S2<T>: Sendable {
  var nc: T // expected-error{{stored property 'nc' of 'Sendable'-conforming generic struct 'S2' has non-sendable type 'T'}}
}

struct S3<T> {
  var c: T
  var array: [T]
}

extension S3: Sendable where T: Sendable { }

enum E1: Sendable {
  case payload(NotConcurrent) // expected-error{{associated value 'payload' of 'Sendable'-conforming enum 'E1' has non-sendable type 'NotConcurrent'}}
}

enum E2<T> {
  case payload(T)
}

extension E2: Sendable where T: Sendable { }

final class C1: Sendable {
  let nc: NotConcurrent? = nil // expected-error{{stored property 'nc' of 'Sendable'-conforming class 'C1' has non-sendable type 'NotConcurrent?'}}
  var x: Int = 0 // expected-error{{stored property 'x' of 'Sendable'-conforming class 'C1' is mutable}}
  let i: Int = 0
}

final class C2: Sendable {
  let x: Int = 0
}

class C3 { }

class C4: C3, UnsafeSendable { // expected-warning{{'UnsafeSendable' is deprecated: Use @unchecked Sendable instead}}
  var y: Int = 0 // okay
}

class C5: UnsafeSendable { // expected-warning{{'UnsafeSendable' is deprecated: Use @unchecked Sendable instead}}
  var x: Int = 0 // okay
}

class C6: C5 {
  var y: Int = 0 // still okay, it's unsafe
}

final class C7<T>: Sendable { }

class C9: Sendable { } // expected-error{{non-final class 'C9' cannot conform to `Sendable`; use `UnsafeSendable`}}

// ----------------------------------------------------------------------
// UnsafeSendable disabling checking
// ----------------------------------------------------------------------
struct S11: UnsafeSendable { // expected-warning{{'UnsafeSendable' is deprecated: Use @unchecked Sendable instead}}
  var nc: NotConcurrent // okay
}

struct S12<T>: UnsafeSendable { // expected-warning{{'UnsafeSendable' is deprecated: Use @unchecked Sendable instead}}
  var nc: T // okay
}

enum E11<T>: UnsafeSendable { // expected-warning{{'UnsafeSendable' is deprecated: Use @unchecked Sendable instead}}
  case payload(NotConcurrent) // okay
  case other(T) // okay
}
