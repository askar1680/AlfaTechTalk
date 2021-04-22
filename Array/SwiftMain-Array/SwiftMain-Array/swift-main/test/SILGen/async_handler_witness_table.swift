// RUN: %target-swift-emit-silgen -sdk %S/Inputs -I %S/Inputs -enable-source-import %s -enable-experimental-concurrency > %t.out
// RUN: %FileCheck -check-prefix=CHECK -check-prefix=CHECK-%target-ptrsize %s < %t.out

// REQUIRES: objc_interop
// REQUIRES: concurrency

import gizmo

func hashEm<H: Hashable>(_ x: H) {}

public class A {
  @asyncHandler
  public func f() {
    hashEm(NSRuncingOptions.mince)
  }
}

// CHECK: sil_witness_table shared [serialized] NSRuncingOptions: Hashable module gizmo
