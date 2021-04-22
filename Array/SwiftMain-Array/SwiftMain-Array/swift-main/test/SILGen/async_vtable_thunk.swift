// RUN: %target-swift-frontend -emit-silgen %s -enable-experimental-concurrency | %FileCheck %s
// REQUIRES: concurrency

class BaseClass<T> {
  func wait() async -> T {}
}

class Derived : BaseClass<Int> {
  override func wait() async -> Int {}
}

// CHECK-LABEL: sil private [thunk] [ossa] @$s18async_vtable_thunk7DerivedC4waitSiyYFAA9BaseClassCADxyYFTV : $@convention(method) @async (@guaranteed Derived) -> @out Int {

