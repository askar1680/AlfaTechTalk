// RUN: %empty-directory(%t)

// RUN: %target-swift-frontend -typecheck -swift-version 5 -module-name FeatureTest -emit-module-interface-path - -enable-library-evolution -enable-experimental-concurrency %s | %FileCheck %s
// REQUIRES: concurrency

// REQUIRES: concurrency

// Ensure that when we emit a Swift interface that makes use of new features,
// the uses of those features are guarded by appropriate #if's that allow older
// compilers to skip over the uses of newer features.

// CHECK: #if compiler(>=5.3) && $Actors
// CHECK-NEXT: public actor MyActor
// CHECK: }
// CHECK-NEXT: #endif
public actor MyActor {
}

// CHECK: #if compiler(>=5.3) && $Actors
// CHECK-NEXT: extension MyActor
public extension MyActor {
  // CHECK-NOT: $Actors
  // CHECK: testFunc
  func testFunc() async { }
  // CHECK: }
  // CHECK-NEXT: #endif
}

// CHECK: #if compiler(>=5.3) && $AsyncAwait
// CHECK-NEXT: globalAsync
// CHECK-NEXT: #endif
public func globalAsync() async { }

// CHECK: #if compiler(>=5.3) && $MarkerProtocol
// CHECK-NEXT: public protocol MP {
// CHECK-NEXT: }
// CHECK-NEXT: #else
// CHECK-NEXT: public typealias MP = Any
// CHECK-NEXT: #endif
@_marker public protocol MP { }

// CHECK: #if compiler(>=5.3) && $MarkerProtocol
// CHECK-NEXT: @_marker public protocol MP2 : FeatureTest.MP {
// CHECK-NEXT: }
// CHECK-NEXT: #else
// CHECK-NEXT: public typealias MP2 = Any
// CHECK-NEXT: #endif
@_marker public protocol MP2: MP { }

// CHECK: #if compiler(>=5.3) && $MarkerProtocol
// CHECK-NEXT: public protocol MP3 : AnyObject, FeatureTest.MP {
// CHECK-NEXT: }
public protocol MP3: AnyObject, MP { }

// CHECK: #if compiler(>=5.3) && $MarkerProtocol
// CHECK-NEXT: extension MP2 {
// CHECK-NEXT: func inMP2
extension MP2 {
  public func inMP2() { }
}

// CHECK: class OldSchool {
public class OldSchool: MP {
  // CHECK: #if compiler(>=5.3) && $AsyncAwait
  // CHECK-NEXT: takeClass()
  // CHECK-NEXT: #endif
  public func takeClass() async { }
}

// CHECK: class OldSchool2 {
public class OldSchool2: MP {
  // CHECK: #if compiler(>=5.3) && $AsyncAwait
  // CHECK-NEXT: takeClass()
  // CHECK-NEXT: #endif
  public func takeClass() async { }
}

// CHECK: #if compiler(>=5.3) && $RethrowsProtocol
// CHECK-NEXT: @rethrows public protocol RP
@rethrows public protocol RP {
  func f() throws -> Bool
}

// CHECK: public struct UsesRP {
public struct UsesRP {
  // CHECK: #if compiler(>=5.3) && $RethrowsProtocol
  // CHECK-NEXT:  public var value: FeatureTest.RP? {
  // CHECK-NOT: #if compiler(>=5.3) && $RethrowsProtocol
  // CHECK: get
  public var value: RP? {
    nil
  }
}

// CHECK: #if compiler(>=5.3) && $RethrowsProtocol
// CHECK-NEXT: public struct IsRP
public struct IsRP: RP {
  // CHECK-NEXT: public func f()
  public func f() -> Bool { }

  // CHECK-NOT: $RethrowsProtocol
  // CHECK-NEXT: public var isF: 
  // CHECK-NEXT: get
  public var isF: Bool {
    f()
  }
}

// CHECK: #if compiler(>=5.3) && $RethrowsProtocol
// CHECK-NEXT: public func acceptsRP
public func acceptsRP<T: RP>(_: T) { }

// CHECK: #if compiler(>=5.3) && $MarkerProtocol
// CHECK-NEXT: extension Array : FeatureTest.MP where Element : FeatureTest.MP {
extension Array: FeatureTest.MP where Element : FeatureTest.MP { }
// CHECK: }

// CHECK: #if compiler(>=5.3) && $MarkerProtocol
// CHECK-NEXT: extension OldSchool : Swift.UnsafeSendable {
extension OldSchool: UnsafeSendable { }
// CHECK-NEXT: }

// CHECK: #if compiler(>=5.3) && $GlobalActors
// CHECK-NEXT: @globalActor public struct SomeGlobalActor
@globalActor
public struct SomeGlobalActor {
  public static let shared = MyActor()
}


// CHECK: #if compiler(>=5.3) && $AsyncAwait
// CHECK-NEXT: func runSomethingSomewhere
// CHECK-NEXT: #endif
public func runSomethingSomewhere(body: () async -> Void) { }

// CHECK: #if compiler(>=5.3) && $Sendable
// CHECK-NEXT: func runSomethingConcurrently(body: @Sendable () -> 
// CHECK-NEXT: #endif
public func runSomethingConcurrently(body: @Sendable () -> Void) { }

// CHECK: #if compiler(>=5.3) && $Actors
// CHECK-NEXT: func stage
// CHECK-NEXT: #endif
public func stage(with actor: MyActor) { }

// CHECK-NOT: extension MyActor : Swift.Sendable

// CHECK: #if compiler(>=5.3) && $MarkerProtocol
// CHECK-NEXT: extension OldSchool : FeatureTest.MP {
// CHECK-NEXT: #endif

