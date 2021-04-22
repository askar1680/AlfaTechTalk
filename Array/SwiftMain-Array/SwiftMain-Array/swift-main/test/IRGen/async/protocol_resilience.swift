// RUN: %empty-directory(%t)
// RUN: %target-swift-frontend -emit-module -enable-experimental-concurrency -g -enable-library-evolution -emit-module-path=%t/resilient_protocol.swiftmodule -module-name=resilient_protocol %S/Inputs/resilient_protocol.swift
// RUN: %target-swift-frontend -I %t -emit-ir -enable-experimental-concurrency -g -enable-library-evolution %s | %FileCheck --check-prefix=CHECK --check-prefix=CHECK-%target-cpu %s
// REQUIRES: concurrency

import resilient_protocol

public protocol MyAwaitable {
  associatedtype Result

  func wait() async -> Int

  func wait() async -> Result

  func waitThrows() async throws -> Int

  func waitThrows() async throws -> Result

  // FIXME
  // func waitGeneric<T>(_: T) async -> Result
  // func waitGenericThrows<T>(_: T) async throws -> Result
}

// CHECK-LABEL: @"$s19protocol_resilience11MyAwaitableP4wait6ResultQzyYFTjTu" = {{(dllexport )?}}{{(protected )?}}global %swift.async_func_pointer

// CHECK-LABEL: @"$s19protocol_resilience19ConformsToAwaitableVyxG010resilient_A00E0AAMc" = hidden constant
// CHECK-SAME: %swift.async_func_pointer* @"$s19protocol_resilience19ConformsToAwaitableVyxG010resilient_A00E0AaeFP4wait6ResultQzyYFTWTu"

// CHECK-LABEL: define {{(dllexport )?}}{{(protected )?}}swift{{(tail)?}}cc void @"$s19protocol_resilience14callsAwaitabley6ResultQzxY010resilient_A00D0RzlF"(%swift.opaque* noalias nocapture %0, %swift.context* swiftasync %1, %swift.opaque* noalias nocapture %2, %swift.type* %T, i8** %T.Awaitable)
// CHECK: %swift.async_func_pointer* @"$s18resilient_protocol9AwaitableP4wait6ResultQzyYFTjTu"
// CHECK: ret void
public func callsAwaitable<T : Awaitable>(_ t: T) async -> T.Result {
  return await t.wait()
}

// CHECK-LABEL: define {{(dllexport )?}}{{(protected )?}}swift{{(tail)?}}cc void @"$s19protocol_resilience11MyAwaitableP4wait6ResultQzyYFTj"(%swift.opaque* noalias nocapture %0, %swift.context* swiftasync %1, %swift.opaque* noalias nocapture swiftself %2, %swift.type* %3, i8** %4)

struct ConformsToAwaitable<T> : Awaitable {
  var value: T

  func wait() async -> T {
    return value
  }
}
