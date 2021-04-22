// RUN: %empty-directory(%t)
// RUN: %target-swift-frontend -emit-module -emit-module-path %t/ShadowsConcur.swiftmodule -module-name ShadowsConcur %S/Inputs/ShadowsConcur.swift
// RUN: %target-typecheck-verify-swift -I %t -enable-experimental-concurrency
// REQUIRES: concurrency


import ShadowsConcur

func f(_ t : Task) -> Bool {
  return t.someProperty == "123"
}

func g(_: _Concurrency.Task) {}
