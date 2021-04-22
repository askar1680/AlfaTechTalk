// RUN: %target-swift-ide-test -print-module -module-to-print=LinkedRecords -I %S/Inputs/ -source-filename=x -enable-cxx-interop | %FileCheck %s

// CHECK: extension Space {
// CHECK:   struct C {
// CHECK:     struct D {
// CHECK:       var B: Space.A.B
// CHECK:       init(B: Space.A.B)
// CHECK:     }
// CHECK:   }
// CHECK:   struct A {
// CHECK:     struct B {
// CHECK:       init(_: Int32)
// CHECK:       init(_: CChar)
// CHECK:     }
// CHECK:     init()
// CHECK:   }
// CHECK:   struct E {
// CHECK:     init()
// CHECK:     static func test(_: UnsafePointer<Space.C>!)
// CHECK:   }
// CHECK: }

// CHECK: struct M {
// CHECK:   init()
// CHECK: }
// CHECK: struct F {
// CHECK:   struct __Unnamed_union___Anonymous_field0 {
// CHECK:     struct __Unnamed_struct_c {
// CHECK:       init()
// CHECK:     }
// CHECK:     var c: F.__Unnamed_union___Anonymous_field0.__Unnamed_struct_c
// CHECK:     var m: M
// CHECK:     init()
// CHECK:     init(c: F.__Unnamed_union___Anonymous_field0.__Unnamed_struct_c)
// CHECK:     init(m: M)
// CHECK:   }
// CHECK:   var __Anonymous_field0: F.__Unnamed_union___Anonymous_field0
// CHECK:   var c: F.__Unnamed_union___Anonymous_field0.__Unnamed_struct_c
// CHECK:   var m: M
// CHECK:   var m2: M
// CHECK:   init()
// CHECK:   init(_ __Anonymous_field0: F.__Unnamed_union___Anonymous_field0, m2: M)
// CHECK: }
