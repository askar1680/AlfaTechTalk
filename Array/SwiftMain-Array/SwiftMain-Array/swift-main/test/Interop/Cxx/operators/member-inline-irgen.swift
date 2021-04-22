// RUN: %target-swift-emit-ir %s -I %S/Inputs -enable-cxx-interop | %FileCheck %s
//
// We can't yet call member functions correctly on Windows (SR-13129).
// XFAIL: OS=windows-msvc

import MemberInline

public func sub(_ lhs: inout LoadableIntWrapper, _ rhs: LoadableIntWrapper) -> LoadableIntWrapper { lhs - rhs }

// CHECK: call [[RES:i32|i64]] [[NAME:@(_ZN18LoadableIntWrappermiES_|"\?\?GLoadableIntWrapper@@QEAA\?AU0@U0@@Z")]](%struct.LoadableIntWrapper* {{%[0-9]+}}, {{i32|\[1 x i32\]|i64|%struct.LoadableIntWrapper\* byval\(.*\) align 4}} {{%[0-9]+}})
// CHECK: define linkonce_odr [[RES]] [[NAME]](%struct.LoadableIntWrapper* nonnull dereferenceable(4) {{.*}}, {{i32 %rhs.coerce|\[1 x i32\] %rhs.coerce|i64 %rhs.coerce|%struct.LoadableIntWrapper\* byval\(%struct.LoadableIntWrapper\) align 4 %rhs}})

public func call(_ wrapper: inout LoadableIntWrapper, _ arg: Int32) -> Int32 { wrapper(arg) }

// CHECK: call [[RES:i32|i64]] [[NAME:@(_ZN18LoadableIntWrapperclEi|"\?\?GLoadableIntWrapper@@QEAAHH@Z")]](%struct.LoadableIntWrapper* {{%[0-9]+}}, {{i32|\[1 x i32\]|i64|%struct.LoadableIntWrapper\* byval\(.*\) align 4}} {{%[0-9]+}})
// CHECK: define linkonce_odr [[RES]] [[NAME]](%struct.LoadableIntWrapper* nonnull dereferenceable(4) {{.*}}, {{i32 %x|\[1 x i32\] %x|i64 %x|%struct.LoadableIntWrapper\* byval\(%struct.LoadableIntWrapper\) align 4 %rhs}})

public func call(_ wrapper: inout AddressOnlyIntWrapper) -> Int32 { wrapper() }

// CHECK: call [[RES:i32|i64]] [[NAME:@(_ZN21AddressOnlyIntWrapperclEv|"\?\?GAddressOnlyIntWrapper@@QEAAHXZ")]](%struct.AddressOnlyIntWrapper* {{%[0-9]+}})
// CHECK: define linkonce_odr [[RES]] [[NAME]](%struct.AddressOnlyIntWrapper* nonnull dereferenceable(4) {{.*}})
