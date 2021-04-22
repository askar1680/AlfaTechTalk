// RUN: %empty-directory(%t)
// RUN: %target-swift-frontend -emit-module -o %t/Test.swiftmodule -emit-module-interface-path %t/Test.swiftinterface -module-name Test -enable-experimental-concurrency %s
// RUN: %FileCheck %s --check-prefix FROMSOURCE --check-prefix CHECK < %t/Test.swiftinterface
// RUN: %target-swift-frontend -typecheck-module-from-interface -module-name Test %t/Test.swiftinterface

// RUN: %target-swift-frontend -emit-module -o /dev/null -merge-modules %t/Test.swiftmodule -disable-objc-attr-requires-foundation-module -emit-module-interface-path %t/TestFromModule.swiftinterface -module-name Test -enable-experimental-concurrency
// RUN: %FileCheck %s --check-prefix FROMMODULE --check-prefix CHECK < %t/TestFromModule.swiftinterface
// RUN: %target-swift-frontend -typecheck-module-from-interface -module-name Test %t/TestFromModule.swiftinterface

// REQUIRES: concurrency

// CHECK: public actor SomeActor
public actor SomeActor {
  @actorIndependent func maine() { }
}

// CHECK: @globalActor public struct SomeGlobalActor
@globalActor
public struct SomeGlobalActor {
  public static let shared = SomeActor()
}

// CHECK: @{{(Test.)?}}SomeGlobalActor public protocol P1
// CHECK-NEXT: @{{(Test.)?}}SomeGlobalActor func method()
@SomeGlobalActor
public protocol P1 {
  func method()
}

// CHECK: class C1
// CHECK-NEXT: @{{(Test.)?}}SomeGlobalActor public func method()
public class C1: P1 {
  public func method() { }
}

@SomeGlobalActor
public class C2 { }

// CHECK: @{{(Test.)?}}SomeGlobalActor public class C2
public class C3: C2 { }

// CHECK: public actor SomeSubActor
// CHECK-NEXT: @actorIndependent public func maine()
public actor SomeSubActor: SomeActor {
  override public func maine() { }
}
