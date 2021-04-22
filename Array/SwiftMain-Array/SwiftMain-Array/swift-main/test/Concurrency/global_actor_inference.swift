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

@globalActor
struct GenericGlobalActor<T> {
  static var shared: SomeActor { SomeActor() }
}

// ----------------------------------------------------------------------
// Check that MainActor exists
// ----------------------------------------------------------------------

@MainActor protocol Aluminium {
  func method()
}
@MainActor class Copper {}
@MainActor func iron() {}

// ----------------------------------------------------------------------
// Check that @MainActor(blah) doesn't work
// ----------------------------------------------------------------------
// expected-error@+1{{global actor attribute 'MainActor' argument can only be '(unsafe)'}}
@MainActor(blah) func brokenMainActorAttr() { }

// ----------------------------------------------------------------------
// Global actor inference for protocols
// ----------------------------------------------------------------------

@SomeGlobalActor
protocol P1 {
  func method()
}

protocol P2 {
  @SomeGlobalActor func method1() // expected-note {{'method1()' declared here}}
  func method2()
}

class C1: P1 {
  func method() { } // expected-note 2 {{calls to instance method 'method()' from outside of its actor context are implicitly asynchronous}}

  @OtherGlobalActor func testMethod() {
    method() // expected-error {{instance method 'method()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}
    _ = method  // expected-error {{instance method 'method()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}
  }
}

class C2: P2 {
  func method1() { }  // expected-note 2{{calls to instance method 'method1()' from outside of its actor context are implicitly asynchronous}}
  func method2() { }

  @OtherGlobalActor func testMethod() {
    method1() // expected-error{{instance method 'method1()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}
    _ = method1 // expected-error{{instance method 'method1()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}
    method2() // okay
  }
}

// ----------------------------------------------------------------------
// Global actor inference for classes and extensions
// ----------------------------------------------------------------------
@SomeGlobalActor class C3 {
  func method1() { }  // expected-note 2{{calls to instance method 'method1()' from outside of its actor context are implicitly asynchronous}}
}

extension C3 {
  func method2() { }  // expected-note 2{{calls to instance method 'method2()' from outside of its actor context are implicitly asynchronous}}
}

class C4: C3 {
  func method3() { }  // expected-note 2{{calls to instance method 'method3()' from outside of its actor context are implicitly asynchronous}}
}

extension C4 {
  func method4() { }  // expected-note 2{{calls to instance method 'method4()' from outside of its actor context are implicitly asynchronous}}
}

class C5 {
  func method1() { }
}

@SomeGlobalActor extension C5 {
  func method2() { }  // expected-note 2{{calls to instance method 'method2()' from outside of its actor context are implicitly asynchronous}}
}

@OtherGlobalActor func testGlobalActorInference(c3: C3, c4: C4, c5: C5) {
  // Propagation via class annotation
  c3.method1() // expected-error{{instance method 'method1()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}
  c3.method2() // expected-error{{instance method 'method2()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}
  
  _ = c3.method1  // expected-error{{instance method 'method1()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}
  _ = c3.method2  // expected-error{{instance method 'method2()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}

  // Propagation via subclassing
  c4.method3() // expected-error{{instance method 'method3()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}
  c4.method4() // expected-error{{instance method 'method4()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}

  _ = c4.method3  // expected-error{{instance method 'method3()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}
  _ = c4.method4  // expected-error{{instance method 'method4()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}

  // Propagation in an extension.
  c5.method1() // OK: no propagation
  c5.method2() // expected-error{{instance method 'method2()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}

  _ = c5.method1  // OK
  _ = c5.method2 // expected-error{{instance method 'method2()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'OtherGlobalActor'}}
}

protocol P3 {
  @OtherGlobalActor func method1() // expected-note{{'method1()' declared here}}
  func method2()
}

class C6: P2, P3 {
  func method1() { }
    // expected-error@-1{{instance method 'method1()' must be isolated to the global actor 'SomeGlobalActor' to satisfy corresponding requirement from protocol 'P2'}}
    // expected-error@-2{{instance method 'method1()' must be isolated to the global actor 'OtherGlobalActor' to satisfy corresponding requirement from protocol 'P3'}}
  func method2() { }

  func testMethod() {
    method1() // okay: no inference
    method2() // okay: no inference
    let _ = method1 // okay: no inference
    let _ = method2 // okay: no inference
  }
}

// ----------------------------------------------------------------------
// Global actor checking for overrides
// ----------------------------------------------------------------------
actor GenericSuper<T> {
  @GenericGlobalActor<T> func method() { }

  @GenericGlobalActor<T> func method2() { } // expected-note {{overridden declaration is here}}
  @GenericGlobalActor<T> func method3() { } // expected-note {{overridden declaration is here}}
  @GenericGlobalActor<T> func method4() { }
  @GenericGlobalActor<T> func method5() { }
}

actor GenericSub<T> : GenericSuper<[T]> {
  override func method() { }  // expected-note 2{{calls to instance method 'method()' from outside of its actor context are implicitly asynchronous}}

  @GenericGlobalActor<T> override func method2() { } // expected-error{{global actor 'GenericGlobalActor<T>'-isolated instance method 'method2()' has different actor isolation from global actor 'GenericGlobalActor<[T]>'-isolated overridden declaration}}
  nonisolated override func method3() { } // expected-error{{actor-independent instance method 'method3()' has different actor isolation from global actor 'GenericGlobalActor<[T]>'-isolated overridden declaration}}

  @OtherGlobalActor func testMethod() {
    method() // expected-error{{instance method 'method()' isolated to global actor 'GenericGlobalActor<[T]>' can not be referenced from different global actor 'OtherGlobalActor'}}
    _ = method  // expected-error{{instance method 'method()' isolated to global actor 'GenericGlobalActor<[T]>' can not be referenced from different global actor 'OtherGlobalActor'}}
  }
}

// ----------------------------------------------------------------------
// Global actor inference for superclasses
// ----------------------------------------------------------------------
struct Container<T> {
  @GenericGlobalActor<T> class Superclass { }
  @GenericGlobalActor<[T]> class Superclass2 { }
}

struct OtherContainer<U> {
  // Okay to change the global actor in a subclass.
  @GenericGlobalActor<[U]> class Subclass1 : Container<[U]>.Superclass { }
  @GenericGlobalActor<U> class Subclass2 : Container<[U]>.Superclass { }

  // Ensure that substitutions work properly when inheriting.
  class Subclass3<V> : Container<(U, V)>.Superclass2 {
    func method() { } // expected-note{{calls to instance method 'method()' from outside of its actor context are implicitly asynchronous}}

    @OtherGlobalActor func testMethod() async {
      await method()
      let _ = method  // expected-error{{instance method 'method()' isolated to global actor 'GenericGlobalActor<[(U, V)]>' can not be referenced from different global actor 'OtherGlobalActor'}}
    }
  }
}

class SuperclassWithGlobalActors {
  @GenericGlobalActor<Int> func f() { }
  @GenericGlobalActor<Int> func g() { } // expected-note{{overridden declaration is here}}
  func h() { }
  func i() { }
  func j() { }
}

@GenericGlobalActor<String>
class SubclassWithGlobalActors : SuperclassWithGlobalActors {
  override func f() { } // okay: inferred to @GenericGlobalActor<Int>

  @GenericGlobalActor<String> override func g() { } // expected-error{{global actor 'GenericGlobalActor<String>'-isolated instance method 'g()' has different actor isolation from global actor 'GenericGlobalActor<Int>'-isolated overridden declaration}}

  override func h() { } // okay: inferred to unspecified

  func onGenericGlobalActorString() { }
  @GenericGlobalActor<Int> func onGenericGlobalActorInt() { }

  @asyncHandler @GenericGlobalActor<String>
  override func i() { // okay to differ from superclass because it's an asyncHandler.
    onGenericGlobalActorString()
  }

  @asyncHandler
  override func j() { // okay, isolated to GenericGlobalActor<String>
    onGenericGlobalActorString() // okay
    onGenericGlobalActorInt() // expected-error{{call is 'async' but is not marked with 'await'}}
  }
}

// ----------------------------------------------------------------------
// Global actor inference for unspecified contexts
// ----------------------------------------------------------------------

// expected-note@+1 {{calls to global function 'foo()' from outside of its actor context are implicitly asynchronous}}
@SomeGlobalActor func foo() { sibling() }

@SomeGlobalActor func sibling() { foo() }

func bar() async {
  foo() // expected-error{{call is 'async' but is not marked with 'await'}}
}

// expected-note@+1 {{add '@SomeGlobalActor' to make global function 'barSync()' part of global actor 'SomeGlobalActor'}} {{1-1=@SomeGlobalActor }}
func barSync() {
  foo() // expected-error {{global function 'foo()' isolated to global actor 'SomeGlobalActor' can not be referenced from this synchronous context}}
}

// ----------------------------------------------------------------------
// Property wrappers
// ----------------------------------------------------------------------

@propertyWrapper
@OtherGlobalActor
struct WrapperOnActor<Wrapped> {
  @actorIndependent(unsafe) private var stored: Wrapped

  nonisolated init(wrappedValue: Wrapped) {
    stored = wrappedValue
  }

  @MainActor var wrappedValue: Wrapped {
    get { stored }
    set { stored = newValue }
  }

  @SomeGlobalActor var projectedValue: Wrapped {
    get { stored }
    set { stored = newValue }
  }
}

@propertyWrapper
actor WrapperActor<Wrapped> {
  @actorIndependent(unsafe) var storage: Wrapped

  init(wrappedValue: Wrapped) {
    storage = wrappedValue
  }

  nonisolated var wrappedValue: Wrapped {
    get { storage }
    set { storage = newValue }
  }

  nonisolated var projectedValue: Wrapped {
    get { storage }
    set { storage = newValue }
  }
}

struct HasWrapperOnActor {
  @WrapperOnActor var synced: Int = 0
  // expected-note@-1 3{{property declared here}}

  // expected-note@+1 3{{to make instance method 'testErrors()'}}
  func testErrors() {
    _ = synced // expected-error{{property 'synced' isolated to global actor 'MainActor' can not be referenced from this synchronous context}}
    _ = $synced // expected-error{{property '$synced' isolated to global actor 'SomeGlobalActor' can not be referenced from this synchronous context}}
    _ = _synced // expected-error{{property '_synced' isolated to global actor 'OtherGlobalActor' can not be referenced from this synchronous context}}
  }

  @MainActor mutating func testOnMain() {
    _ = synced
    synced = 17
  }

  @WrapperActor var actorSynced: Int = 0

  func testActorSynced() {
    _ = actorSynced
    _ = $actorSynced
    _ = _actorSynced
  }
}


@propertyWrapper
actor WrapperActorBad1<Wrapped> {
  var storage: Wrapped

  init(wrappedValue: Wrapped) {
    storage = wrappedValue
  }

  var wrappedValue: Wrapped { // expected-error{{'wrappedValue' property in property wrapper type 'WrapperActorBad1' cannot be isolated to the actor instance; consider 'nonisolated'}}}}
    get { storage }
    set { storage = newValue }
  }
}

@propertyWrapper
actor WrapperActorBad2<Wrapped> {
  @actorIndependent(unsafe) var storage: Wrapped

  init(wrappedValue: Wrapped) {
    storage = wrappedValue
  }

  nonisolated var wrappedValue: Wrapped {
    get { storage }
    set { storage = newValue }
  }

  var projectedValue: Wrapped { // expected-error{{'projectedValue' property in property wrapper type 'WrapperActorBad2' cannot be isolated to the actor instance; consider 'nonisolated'}}
    get { storage }
    set { storage = newValue }
  }
}

actor ActorWithWrapper {
  @WrapperOnActor var synced: Int = 0
  // expected-note@-1 3{{property declared here}}
  func f() {
    _ = synced // expected-error{{'synced' isolated to global actor}}
    _ = $synced // expected-error{{'$synced' isolated to global actor}}
    _ = _synced // expected-error{{'_synced' isolated to global actor}}
  }
}

// ----------------------------------------------------------------------
// Unsafe global actors
// ----------------------------------------------------------------------
protocol UGA {
  @SomeGlobalActor(unsafe) func req() // expected-note{{calls to instance method 'req()' from outside of its actor context are implicitly asynchronous}}
}

struct StructUGA1: UGA {
  @SomeGlobalActor func req() { }
}

struct StructUGA2: UGA {
  nonisolated func req() { }
}

@SomeGlobalActor
struct StructUGA3: UGA {
  func req() {
    sibling()
  }
}

@GenericGlobalActor<String>
func testUGA<T: UGA>(_ value: T) {
  value.req() // expected-error{{instance method 'req()' isolated to global actor 'SomeGlobalActor' can not be referenced from different global actor 'GenericGlobalActor<String>'}}
}

class UGAClass {
  @SomeGlobalActor(unsafe) func method() { }
}

class UGASubclass1: UGAClass {
  @SomeGlobalActor override func method() { }
}

class UGASubclass2: UGAClass {
  override func method() { }
}

@propertyWrapper
@OtherGlobalActor(unsafe)
struct WrapperOnUnsafeActor<Wrapped> {
  @actorIndependent(unsafe) private var stored: Wrapped

  init(wrappedValue: Wrapped) {
    stored = wrappedValue
  }

  @MainActor(unsafe) var wrappedValue: Wrapped {
    get { stored }
    set { stored = newValue }
  }

  @SomeGlobalActor(unsafe) var projectedValue: Wrapped {
    get { stored }
    set { stored = newValue }
  }
}

struct HasWrapperOnUnsafeActor {
  @WrapperOnUnsafeActor var synced: Int = 0
  // expected-note@-1 3{{property declared here}}

  func testUnsafeOkay() {
    _ = synced
    _ = $synced
    _ = _synced
  }

  nonisolated func testErrors() {
    _ = synced // expected-error{{property 'synced' isolated to global actor 'MainActor' can not be referenced from}}
    _ = $synced // expected-error{{property '$synced' isolated to global actor 'SomeGlobalActor' can not be referenced from}}
    _ = _synced // expected-error{{property '_synced' isolated to global actor 'OtherGlobalActor' can not be referenced from}}
  }

  @MainActor mutating func testOnMain() {
    _ = synced
    synced = 17
  }
}
