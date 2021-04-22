// REQUIRES: concurrency

// RUN: %target-typecheck-verify-swift -enable-experimental-concurrency

// ===================
// Parsing
// ===================

func asyncFunc() async -> Int { }

@completionHandlerAsync("asyncFunc()", completionHandlerIndex: 1)
func goodFunc1(value: String, completionHandler: @escaping (Int) -> Void) {}

@completionHandlerAsync("asyncFunc()")
func goodFunc2(value: String, completionHandler: @escaping (Int) -> Void) {}

// expected-error@+1:24{{expected '(' in 'completionHandlerAsync' attribute}}
@completionHandlerAsync
func func1() {}

// expected-error@+1:25{{argument of 'completionHandlerAsync' attribute must be an identifier or full function name}}
@completionHandlerAsync("not+identifier")
func func2() {}

// expected-error@+1:25{{argument of 'completionHandlerAsync' attribute must be an identifier or full function name}}
@completionHandlerAsync("$dollarname")
func func3() {}

// expected-error@+1:25{{argument of 'completionHandlerAsync' attribute must be an identifier or full function name}}
@completionHandlerAsync("TypePrefix.func")
func func4() {}

// expected-error@+1{{argument of 'completionHandlerAsync' cannot be an interpolated string literal}}
@completionHandlerAsync("interpreted \()")
func func5() {}

@completionHandlerAsync("foo" // expected-error{{expected ')' in 'completionHandlerAsync' attribute}}
func func6() {}

@completionHandlerAsync("foo", completionHandlerIndex: 2 // expected-error@:57{{expected ')' in 'completionHandlerAsync'}}
func func7() {}

// expected-error@+1{{'@completionHandlerAsync' attribute cannot be applied to this declaration}}
@completionHandlerAsync("foo", completionHandlerIndex: 0)
protocol SomeProto {
  // expected-error@+1:27{{no corresponding async function named 'protoFunc'}}
  @completionHandlerAsync("protoFunc", completionHandlerIndex: 0)
  func protoFunc(continuation: @escaping () -> Void)
}

// expected-error@+1{{'@completionHandlerAsync' attribute cannot be applied to this declaration}}
@completionHandlerAsync("foo", completionHandlerIndex: 0)
struct SomeStruct: SomeProto {
  // expected-error@+1:27{{no corresponding async function named 'protoFunc'}}
  @completionHandlerAsync("protoFunc", completionHandlerIndex: 0)
  func protoFunc(continuation: @escaping () -> Void) {}

  func structFunc() async { }

  @completionHandlerAsync("structFunc", completionHandlerIndex: 0)
  func structFunc(continuation: @escaping () -> Void) { }

  static func staticStructFunc() async { }

  @completionHandlerAsync("staticStructFunc", completionHandlerIndex: 0)
  static func staticStructFunc(completionHandler: @escaping () -> Void) { }
}

// expected-error@+1 {{'@completionHandlerAsync' attribute cannot be applied to this declaration}}
@completionHandlerAsync("foo", completionHandlerIndex: 0)
class SomeClass: SomeProto {
  // expected-error@+1:27{{no corresponding async function named 'protoFunc'}}
  @completionHandlerAsync("protoFunc", completionHandlerIndex: 0)
  func protoFunc(continuation: @escaping () -> Void) { }

  func classFunc() async { }

  @completionHandlerAsync("classFunc", completionHandlerIndex: 0)
  func classFunc(completionHandler: @escaping () -> Void) { }
}

// ===================
// Typechecking
// ===================

// expected-error@+1:2{{'@completionHandlerAsync' should be attached to a non-async completion-handler function}}
@completionHandlerAsync("asyncFunc")
func typecheckFunc1() async {} // expected-note@:23{{function declared async}}

// expected-error@+1:2{{'@completionHandlerAsync' should be attached to a non-async completion-handler function}}
@completionHandlerAsync("betterFunc")
func typecheckFunc2() {}

// expected-error@+2:2{{'@completionHandlerAsync' should be attached to a non-async completion-handler function}}
// expected-note@+2:55{{'String' is not a function type}}
@completionHandlerAsync("foo", completionHandlerIndex: 1)
func typecheckFunc3(value: String, completionHandler: String) {}

// expected-error@+2:2{{'@completionHandlerAsync' should be attached to a non-async completion-handler function}}
// expected-note@+2:55{{'String' is not a function type}}
@completionHandlerAsync("foo")
func typecheckFunc4(value: String, completionHandler: String) {}

// expected-error@+2:2{{'@completionHandlerAsync' should be attached to a non-async completion-handler function}}
// expected-note@+2:33{{completion handler must return 'Void'}}
@completionHandlerAsync("betterFunc(param:)")
func typecheckFunc5(value: Int, completionHandler: @escaping (Int) -> Int) {}

// expected-error@+1:56{{completion handler index out of range of the function parameters}}
@completionHandlerAsync("foo", completionHandlerIndex: 2)
func typecheckFunc6(value: Int) { }

// expected-error@+3:2{{'@completionHandlerAsync' should be attached to a non-async completion-handler function}}
// expected-note@+3:21{{completion handler must return 'Void'}}
// expected-note@+2:21{{completion handler must be '@escaping'}}
@completionHandlerAsync("foo", completionHandlerIndex: 0)
func typecheckFunc7(handler: () -> Int) {}

// expected-error@+3:2{{'@completionHandlerAsync' should be attached to a non-async completion-handler function}}
// expected-note@+3:21{{completion handler must be '@escaping'}}
// expected-note@+2:30{{completion handler must not be '@autoclosure'}}
@completionHandlerAsync("foo")
func typecheckFunc8(handler: @autoclosure () -> ()) {}

// ===================
// Decl assignment
// ===================

// expected-error@+1:25{{no corresponding async function named 'functionThatDoesntExist'}}
@completionHandlerAsync("functionThatDoesntExist(_:)")
func typecheckFunc8(handler: @escaping () -> Void) {}

// These two have the same decl name, so they are ambiguous
func matchingAsyncFunc(value: Int) async {} // expected-note{{'matchingAsyncFunc(value:)' declared here}}
func matchingAsyncFunc(value: String) async {} // expected-note{{'matchingAsyncFunc(value:)' declared here}}

// expected-error@+1:25{{ambiguous '@completionHandlerAsync' async function 'matchingAsyncFunc(value:)'}}
@completionHandlerAsync("matchingAsyncFunc(value:)")
func typecheckFunc9(handler: @escaping () -> Void) {}
