// RUN: %target-swift-frontend(mock-sdk: %clang-importer-sdk) -typecheck -I %S/Inputs/custom-modules -enable-experimental-concurrency %s -verify

// REQUIRES: objc_interop
// REQUIRES: concurrency
// REQUIRES: OS=macosx

import Foundation
import ObjCConcurrency

func testSlowServer(slowServer: SlowServer) async throws {
  _ = try await slowServer.oldAPI(); // expected-error{{'oldAPI()' is unavailable in macOS: APIs deprecated as of macOS 10.14 and earlier are not imported as 'async'}}
}
