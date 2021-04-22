// RUN: %target-run-simple-swift(-Xfrontend -enable-experimental-concurrency  %import-libdispatch -parse-as-library)

// REQUIRES: executable_test
// REQUIRES: concurrency
// REQUIRES: libdispatch

import Dispatch

enum HomeworkError: Error, Equatable {
  case dogAteIt(String)
}

func formGreeting(name: String) async -> String {
  return "Hello \(name) from async world"
}

func testSimple(
  name: String, dogName: String, shouldThrow: Bool, doSuspend: Bool
) async {
  print("Testing name: \(name), dog: \(dogName), shouldThrow: \(shouldThrow) doSuspend: \(doSuspend)")

  var completed = false

  let taskHandle: Task.Handle<String, Error> = Task.runDetached {
    let greeting = await formGreeting(name: name)

    // If the intent is to test suspending, wait a bit so the second task
    // can complete.
    if doSuspend {
      print("- Future sleeping")
      await Task.sleep(1_000_000_000)
    }

    if (shouldThrow) {
      print("- Future throwing")
      throw HomeworkError.dogAteIt(dogName + " the dog")
    }

    print("- Future returning normally")
    return greeting + "!"
  }

  // If the intent is not to test suspending, wait a bit so the first task
  // can complete.
  if !doSuspend {
    print("+ Reader sleeping")
    await Task.sleep(1_000_000_000)
  }

  do {
    print("+ Reader waiting for the result")
    let result = try await taskHandle.get()
    completed = true
    print("+ Normal return: \(result)")
    assert(result == "Hello \(name) from async world!")
  } catch HomeworkError.dogAteIt(let badDog) {
    completed = true
    print("+ Error return: HomeworkError.dogAteIt(\(badDog))")
    assert(badDog == dogName + " the dog")
  } catch {
    fatalError("Caught a different exception?")
  }

  assert(completed)
  print("Finished test")
}


@main struct Main {
  static func main() async {
    await testSimple(name: "Ted", dogName: "Hazel", shouldThrow: false, doSuspend: false)
    await testSimple(name: "Ted", dogName: "Hazel", shouldThrow: true, doSuspend: false)
    await testSimple(name: "Ted", dogName: "Hazel", shouldThrow: false, doSuspend: true)
    await testSimple(name: "Ted", dogName: "Hazel", shouldThrow: true, doSuspend: true)

    print("Done")
  }
}
