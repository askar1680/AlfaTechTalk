// RUN: %target-run-simple-swift(-Xfrontend -enable-experimental-concurrency -parse-as-library) | %FileCheck %s --dump-input=always

// REQUIRES: executable_test
// REQUIRES: concurrency
// UNSUPPORTED: OS=windows-msvc

struct Boom: Error {}
struct IgnoredBoom: Error {}

func one() async -> Int { 1 }

func boom() async throws -> Int {
  throw Boom()
}

func test_taskGroup_throws() async {
  let got: Int = await Task.withGroup(resultType: Int.self) { group in
    await group.add { try await boom()  }

    do {
      while let r = try await group.next() {
        print("next: \(r)")
      }
    } catch {
      print("error caught in group: \(error)")

      let gc = group.isCancelled
      print("group cancelled: \(gc)")

      await group.add { () async -> Int in
        let c = Task.isCancelled
        print("task 3 (cancelled: \(c))")
        return 3
      }

      guard let third = try! await group.next() else {
        print("task group failed to get 3")
        return 0
      }

      print("task group returning normally: \(third)")
      return third
    }

    fatalError("Should have thrown and handled inside the catch block")
  }

  // CHECK: error caught in group: Boom()
  // CHECK: group cancelled: false
  // CHECK: task 3 (cancelled: false)
  // CHECK: task group returning normally: 3
  // CHECK: got: 3

  print("got: \(got)")
}


@main struct Main {
  static func main() async {
    await test_taskGroup_throws()
  }
}
