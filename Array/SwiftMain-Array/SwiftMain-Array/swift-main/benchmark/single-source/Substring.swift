//===--- Substring.swift --------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TestsUtils

public let SubstringTest = [
  BenchmarkInfo(name: "EqualStringSubstring", runFunction: run_EqualStringSubstring, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "EqualSubstringString", runFunction: run_EqualSubstringString, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "EqualSubstringSubstring", runFunction: run_EqualSubstringSubstring, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "EqualSubstringSubstringGenericEquatable", runFunction: run_EqualSubstringSubstringGenericEquatable, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "SubstringRemoveFirst1", runFunction: run_SubstringRemoveFirst1, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "SubstringRemoveLast1", runFunction: run_SubstringRemoveLast1, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "LessSubstringSubstring", runFunction: run_LessSubstringSubstring, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "LessSubstringSubstringGenericComparable", runFunction: run_LessSubstringSubstringGenericComparable, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "StringFromLongWholeSubstring", runFunction: run_StringFromLongWholeSubstring, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "StringFromLongWholeSubstringGeneric", runFunction: run_StringFromLongWholeSubstringGeneric, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "SubstringComparable", runFunction: run_SubstringComparable, tags: [.validation, .api, .String],
    setUpFunction: { blackHole(_comparison) }),
  BenchmarkInfo(name: "SubstringEqualString", runFunction: run_SubstringEqualString, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "SubstringEquatable", runFunction: run_SubstringEquatable, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "SubstringFromLongString", runFunction: run_SubstringFromLongString, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "SubstringFromLongStringGeneric", runFunction: run_SubstringFromLongStringGeneric, tags: [.validation, .api, .String]),
  BenchmarkInfo(name: "SubstringTrimmingASCIIWhitespace", runFunction: run_SubstringTrimmingASCIIWhitespace, tags: [.validation, .api, .String]),
]

// A string that doesn't fit in small string storage and doesn't fit in Latin-1
let longWide = "f???as???od???ij???ad???ol???sj???al???sd???jl???as???df???ij???li???sd???j?????sl???di???al???i???"
let (s1, ss1) = equivalentWithDistinctBuffers()
let (s2, ss2) = equivalentWithDistinctBuffers()

let quiteLong = String(repeating: "0", count: 10_000)[...]

@inline(never)
public func run_SubstringFromLongString(_ N: Int) {
  var s = longWide
  s += "!" // ensure the string has a real buffer
  for _ in 1...N*500 {
    blackHole(Substring(s))
  }
}

func create<T : RangeReplaceableCollection, U : Collection>(
  _: T.Type, from source: U
) where T.Element == U.Element {
  blackHole(T(source))
}

@inline(never)
public func run_SubstringFromLongStringGeneric(_ N: Int) {
  var s = longWide
  s += "!" // ensure the string has a real buffer
  for _ in 1...N*500 {
    create(Substring.self, from: s)
  }
}

@inline(never)
public func run_StringFromLongWholeSubstring(_ N: Int) {
  var s0 = longWide
  s0 += "!" // ensure the string has a real buffer
  let s = Substring(s0)
  for _ in 1...N*500 {
    blackHole(String(s))
  }
}

@inline(never)
public func run_StringFromLongWholeSubstringGeneric(_ N: Int) {
  var s0 = longWide
  s0 += "!" // ensure the string has a real buffer
  let s = Substring(s0)
  for _ in 1...N*500 {
    create(String.self, from: s)
  }
}

private func equivalentWithDistinctBuffers() -> (String, Substring) {
  var s0 = longWide
  withUnsafeMutablePointer(to: &s0) { blackHole($0) }
  s0 += "!"

  // These two should be equal but with distinct buffers, both refcounted.
  let a = Substring(s0).dropFirst()
  let b = String(a)
  return (b, a)
}

@inline(never)
public func run_EqualStringSubstring(_ N: Int) {
  let (a, b) = (s1, ss1)
  for _ in 1...N*500 {
    blackHole(a == b)
  }
}

@inline(never)
public func run_EqualSubstringString(_ N: Int) {
  let (a, b) = (s1, ss1)
  for _ in 1...N*500 {
    blackHole(b == a)
  }
}

@inline(never)
public func run_EqualSubstringSubstring(_ N: Int) {
  let (_, a) = (s1, ss1)
  let (_, b) = (s2, ss2)
  for _ in 1...N*500 {
    blackHole(a == b)
  }
}

@inline(never)
public func run_EqualSubstringSubstringGenericEquatable(_ N: Int) {
  let (_, a) = (s1, ss1)
  let (_, b) = (s2, ss2)
  func check<T>(_ x: T, _ y: T) where T : Equatable {
    blackHole(x == y)
  }
  for _ in 1...N*500 {
    check(a, b)
  }
}

@inline(never)
public func run_SubstringRemoveFirst1(_ N: Int) {
  for _ in 1...N {
    var s = quiteLong
    s.removeFirst(1)
    blackHole(s.first == "0")
  }
}

@inline(never)
public func run_SubstringRemoveLast1(_ N: Int) {
  for _ in 1...N {
    var s = quiteLong
    s.removeLast(1)
    blackHole(s.first == "0")
  }
}

/*
func checkEqual<T, U>(_ x: T, _ y: U)
where T : StringProtocol, U : StringProtocol {
  blackHole(x == y)
}

@inline(never)
public func run _EqualStringSubstringGenericStringProtocol(_ N: Int) {
  let (a, b) = (s1, ss1)
  for _ in 1...N*500 {
    checkEqual(a, b)
  }
}

@inline(never)
public func run _EqualSubstringStringGenericStringProtocol(_ N: Int) {
  let (a, b) = (s1, ss1)
  for _ in 1...N*500 {
    checkEqual(b, a)
  }
}

@inline(never)
public func run _EqualSubstringSubstringGenericStringProtocol(_ N: Int) {
  let (_, a) = (s1, ss1)
  let (_, b) = (s2, ss2)
  for _ in 1...N*500 {
    checkEqual(a, b)
  }
}
*/

//===----------------------------------------------------------------------===//

/*
@inline(never)
public func run _LessStringSubstring(_ N: Int) {
  let (a, b) = (s1, ss1)
  for _ in 1...N*500 {
    blackHole(a < b)
  }
}

@inline(never)
public func run _LessSubstringString(_ N: Int) {
  let (a, b) = (s1, ss1)
  for _ in 1...N*500 {
    blackHole(b < a)
  }
}
*/

@inline(never)
public func run_LessSubstringSubstring(_ N: Int) {
  let (_, a) = (s1, ss1)
  let (_, b) = (s2, ss2)
  for _ in 1...N*500 {
    blackHole(a < b)
  }
}

@inline(never)
public func run_LessSubstringSubstringGenericComparable(_ N: Int) {
  let (_, a) = (s1, ss1)
  let (_, b) = (s2, ss2)
  func check<T>(_ x: T, _ y: T) where T : Comparable {
    blackHole(x < y)
  }
  for _ in 1...N*500 {
    check(a, b)
  }
}

@inline(never)
public func run_SubstringEquatable(_ N: Int) {
	var string = "pen,pineapple,apple,pen"
	string += ",??????,????,????,??????"
	let substrings = string.split(separator: ",")
	var count = 0
	for _ in 1...N*500 {
		for s in substrings {
			if substrings.contains(s) { count = count &+ 1 }
		}
	}
  CheckResults(count == 8*N*500)
}

@inline(never)
public func run_SubstringEqualString(_ N: Int) {
	var string = "pen,pineapple,apple,pen"
	string += ",??????,????,????,??????"
	let substrings = string.split(separator: ",")
	let pineapple = "pineapple"
	let apple = "????"
	var count = 0
	for _ in 1...N*500 {
		for s in substrings {
			if s == pineapple || s == apple { count = count &+ 1 }
		}
	}
  CheckResults(count == 2*N*500)
}

let _substrings = "pen,pineapple,apple,pen,??????,????,????,??????".split(separator: ",")
let _comparison = _substrings + ["PPAP"]

@inline(never)
public func run_SubstringComparable(_ N: Int) {
	let substrings = _substrings // without this alias, there was 25% slowdown
	let comparison = _comparison // due to increased retain/release traffic ??????????
	var count = 0
	for _ in 1...N*500 {
		if substrings.lexicographicallyPrecedes(comparison) {
			count = count &+ 1
		}
	}
  CheckResults(count == N*500)
}

extension Character {
  fileprivate var isASCIIWhitespace: Bool {
    return self == " " || self == "\t" || self == "\r" || self == "\n" || self == "\r\n"
  }
}

extension Substring {
  fileprivate func trimWhitespace() -> Substring {
    var me = self
    while me.first?.isASCIIWhitespace == .some(true) {
      me = me.dropFirst()
    }
    while me.last?.isASCIIWhitespace == .some(true) {
      me = me.dropLast()
    }
    return me
  }
}

let _trimmableSubstrings = "pineapple,????,  pineapple\t,\r\n\r\n\r\n, ???? ,".split(separator: ",")

@inline(never)
public func run_SubstringTrimmingASCIIWhitespace(_ N: Int) {
  let substrings = _trimmableSubstrings // bringing this alias from above
  var count = 0
  for _ in 1...N*100 {
    for substring in substrings {
      blackHole(substring.trimWhitespace())
    }
  }
}

/*
func checkLess<T, U>(_ x: T, _ y: U)
where T : StringProtocol, U : StringProtocol {
  blackHole(x < y)
}

@inline(never)
public func run _LessStringSubstringGenericStringProtocol(_ N: Int) {
  let (a, b) = (s1, ss1)
  for _ in 1...N*500 {
    checkLess(a, b)
  }
}

@inline(never)
public func run _LessSubstringStringGenericStringProtocol(_ N: Int) {
  let (a, b) = (s1, ss1)
  for _ in 1...N*500 {
    checkLess(b, a)
  }
}

@inline(never)
public func run _LessSubstringSubstringGenericStringProtocol(_ N: Int) {
  let (_, a) = (s1, ss1)
  let (_, b) = (s2, ss2)
  for _ in 1...N*500 {
    checkLess(a, b)
  }
}
*/
