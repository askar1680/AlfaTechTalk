// RUN: %target-typecheck-verify-swift -enable-experimental-concurrency
// REQUIRES: concurrency

actor SomeActor { }

@globalActor
struct SomeGlobalActor {
  static let shared = SomeActor()
}

@globalActor
struct OtherGlobalActor {
  static let shared = SomeActor()
}

func testConversions(f: @escaping @SomeGlobalActor (Int) -> Void, g: @escaping (Int) -> Void) {
  let _: Int = f // expected-error{{cannot convert value of type '@SomeGlobalActor (Int) -> Void' to specified type 'Int'}}

  let _: (Int) -> Void = f // expected-error{{converting function value of type '@SomeGlobalActor (Int) -> Void' to '(Int) -> Void' loses global actor 'SomeGlobalActor'}}
  let _: @SomeGlobalActor (Int) -> Void = g // okay

  // FIXME: this could be better.
  let _: @OtherGlobalActor (Int) -> Void = f // expected-error{{cannot convert value of type 'SomeGlobalActor' to specified type 'OtherGlobalActor'}}
}

@SomeGlobalActor func onSomeGlobalActor() -> Int { 5 }
@SomeGlobalActor(unsafe) func onSomeGlobalActorUnsafe() -> Int { 5 }

@OtherGlobalActor func onOtherGlobalActor() -> Int { 5 } // expected-note{{calls to global function 'onOtherGlobalActor()' from outside of its actor context are implicitly asynchronous}}
@OtherGlobalActor(unsafe) func onOtherGlobalActorUnsafe() -> Int { 5 }  // expected-note 2{{calls to global function 'onOtherGlobalActorUnsafe()' from outside of its actor context are implicitly asynchronous}}

func someSlowOperation() async -> Int { 5 }

func acceptOnSomeGlobalActor<T>(_: @SomeGlobalActor () -> T) { }

func testClosures() async {
  // Global actors on synchronous closures become part of the type
  let cl1 = { @SomeGlobalActor in
    onSomeGlobalActor()
  }
  let _: Double = cl1 // expected-error{{cannot convert value of type '@SomeGlobalActor () -> Int' to specified type 'Double'}}

  // Global actors on async closures do not become part of the type
  let cl2 = { @SomeGlobalActor in
    await someSlowOperation()
  }
  let _: Double = cl2 // expected-error{{cannot convert value of type '() async -> Int' to specified type 'Double'}}

  // okay to be explicit
  acceptOnSomeGlobalActor { @SomeGlobalActor in
    onSomeGlobalActor()
  }

  // Infer from context
  acceptOnSomeGlobalActor {
    onSomeGlobalActor()
  }

  acceptOnSomeGlobalActor { () -> Int in
    let i = onSomeGlobalActor()
    return i
  }

  acceptOnSomeGlobalActor { () -> Int in
    let i = onOtherGlobalActorUnsafe() // expected-error{{global function 'onOtherGlobalActorUnsafe()' isolated to global actor 'OtherGlobalActor' can not be referenced from different global actor 'SomeGlobalActor' in a synchronous context}}
    return i
  }
}

func testClosuresOld() {
  acceptOnSomeGlobalActor { () -> Int in
    let i = onSomeGlobalActor()
    return i
  }

  acceptOnSomeGlobalActor { () -> Int in
    let i = onSomeGlobalActorUnsafe()
    return i
  }

  acceptOnSomeGlobalActor { () -> Int in
    let i = onOtherGlobalActor() // expected-error{{global function 'onOtherGlobalActor()' isolated to global actor 'OtherGlobalActor' can not be referenced from different global actor 'SomeGlobalActor' in a synchronous context}}
    return i
  }

  acceptOnSomeGlobalActor { () -> Int in
    let i = onOtherGlobalActorUnsafe()
    return i
  }

  acceptOnSomeGlobalActor { @SomeGlobalActor () -> Int in
    let i = onOtherGlobalActorUnsafe() // expected-error{{global function 'onOtherGlobalActorUnsafe()' isolated to global actor 'OtherGlobalActor' can not be referenced from different global actor 'SomeGlobalActor' in a synchronous context}}
    return i
  }
}

// Test conversions that happen in various structural positions.
struct X<T> { } // expected-note{{arguments to generic parameter 'T' ('() -> Void' and '@SomeGlobalActor () -> Void') are expected to be equal}}

func f(_: (@SomeGlobalActor () -> Void)?) { }

func g(fn: (() -> Void)?) {
  f(fn)
}

func f2(_ x: X<@SomeGlobalActor () -> Void>) {
  g2(x) // expected-error{{converting function value of type '@SomeGlobalActor () -> Void' to '() -> Void' loses global actor 'SomeGlobalActor'}}
}
func g2(_ x: X<() -> Void>) {
  f2(x) // expected-error{{cannot convert value of type 'X<() -> Void>' to expected argument type 'X<@SomeGlobalActor () -> Void>'}}
}
