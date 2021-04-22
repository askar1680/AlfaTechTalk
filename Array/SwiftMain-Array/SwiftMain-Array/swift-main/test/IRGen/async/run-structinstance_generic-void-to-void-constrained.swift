// RUN: %empty-directory(%t)
// RUN: %target-build-swift -Xfrontend -enable-experimental-concurrency -g %s -emit-ir -parse-as-library -module-name main | %FileCheck %s --check-prefix=CHECK-LL
// RUN: %target-build-swift -Xfrontend -enable-experimental-concurrency -g %s -parse-as-library -module-name main -o %t/main %target-rpath(%t) 
// RUN: %target-codesign %t/main
// RUN: %target-run %t/main | %FileCheck %s

// REQUIRES: executable_test
// REQUIRES: swift_test_mode_optimize_none
// REQUIRES: concurrency
// UNSUPPORTED: use_os_stdlib

import _Concurrency

protocol Fooable {}
extension String: Fooable {}

extension Optional where Wrapped: Fooable {
  // CHECK-LL: @"$sSq4mainAA7FooableRzlE22theConstrainedFunctionyyYFTu" = hidden global %swift.async_func_pointer
  // CHECK-LL: define hidden swift{{(tail)?}}cc void @"$sSq4mainAA7FooableRzlE22theConstrainedFunctionyyYF"(
  func theConstrainedFunction() async {
    // CHECK: running Optional<String>.theConstrainedFunction
    print("running \(Self.self).theConstrainedFunction")
  }
}

@main struct Main {
  static func main() async {
    let a: String? = nil
    await a.theConstrainedFunction()
  }
}
