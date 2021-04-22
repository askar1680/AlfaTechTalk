// RUN: %target-swift-frontend -emit-ir %s -swift-version 5 -enable-experimental-concurrency | %IRGenFileCheck %s
// REQUIRES: concurrency

// rdar_72047158
// XFAIL: CPU=arm64e

// CHECK: %T11actor_class7MyClassC = type <{ %swift.refcounted, %swift.defaultactor, %TSi }>
// CHECK: %swift.defaultactor = type { [10 x i8*] }

// CHECK-objc-LABEL: @"$s11actor_class7MyClassCMm" = global
// CHECK-objc-SAME: %objc_class* @"OBJC_METACLASS_$__TtCs12_SwiftObject"

// CHECK: @"$s11actor_class7MyClassCMf" = internal global
// CHECK-SAME: @"$s11actor_class7MyClassCfD"
// CHECK-objc-SAME: %objc_class* @"OBJC_CLASS_$__TtCs12_SwiftObject"
// CHECK-nonobjc-SAME: %swift.type* null,
//   Flags: uses Swift refcounting
// CHECK-SAME: i32 2,
//   Instance size
// CHECK-64-SAME: i32 104,
// CHECK-32-SAME: i32 52,
//   Alignment mask
// CHECK-64-SAME: i16 15,
// CHECK-32-SAME: i16 7,
//   Field offset for 'x'
// CHECK-objc-SAME: [[INT]] {{48|96}},

// Type descriptor.
// CHECK-LABEL: @"$s11actor_class9ExchangerCMn" = {{.*}}constant
//   superclass ref, negative bounds, positive bounds, num immediate members, num fields, field offset vector offset
// CHECK-SAME: i32 0, i32 2, i32 [[#CLASS_METADATA_HEADER+8]], i32 8, i32 2, i32 [[#CLASS_METADATA_HEADER+1]],

// Reflection field records.
// CHECK-LABEL: @"$s11actor_class9ExchangerCMF" = internal constant
//   Field descriptor kind, field size, num fields,
//   (artificial var, "BD", ...)
// CHECK-SAME: i16 1, i16 12, i32 2, i32 6,
// CHECK-SAME: @"symbolic BD"

public actor MyClass {
  public var x: Int
  public init() { self.x = 0 }
}

// CHECK-LABEL: define {{.*}}@"$s11actor_class7MyClassC1xSivg"
// CHECK: [[T0:%.*]] = getelementptr inbounds %T11actor_class7MyClassC, %T11actor_class7MyClassC* %0, i32 0, i32 2
// CHECK: [[T1:%.*]] = getelementptr inbounds %TSi, %TSi* [[T0]], i32 0, i32 0
// CHECK: load [[INT]], [[INT]]* [[T1]], align

// CHECK-LABEL: define {{.*}}swiftcc %T11actor_class7MyClassC* @"$s11actor_class7MyClassCACycfc"
// CHECK: swift_defaultActor_initialize
// CHECK-LABEL: ret %T11actor_class7MyClassC*

// CHECK-LABEL: define {{.*}}swiftcc %swift.refcounted* @"$s11actor_class7MyClassCfd"
// CHECK: swift_defaultActor_destroy
// CHECK-LABEL: ret

public actor Exchanger<T> {
  public var value: T

  public init(value: T) { self.value = value }
  public func exchange(newValue: T) -> T {
    let oldValue = value
    value = newValue
    return oldValue
  }
}
// CHECK-LABEL: define{{.*}} void @"$s11actor_class9ExchangerC5valuexvg"(
//   Note that this is one more than the field offset vector offset from
//   the class descriptor, since this is the second field.
// CHECK:         [[T0:%.*]] = getelementptr inbounds [[INT]], [[INT]]* {{.*}}, [[INT]] [[#CLASS_METADATA_HEADER+2]]
// CHECK-NEXT:    [[OFFSET:%.*]] = load [[INT]], [[INT]]* [[T0]], align
// CHECK-NEXT:    [[T0:%.*]] = bitcast %T11actor_class9ExchangerC* %1 to i8*
// CHECK-NEXT:    getelementptr inbounds i8, i8* [[T0]], [[INT]] [[OFFSET]]
