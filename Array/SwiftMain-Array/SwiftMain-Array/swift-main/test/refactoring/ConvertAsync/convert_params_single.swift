func withError(_ completion: (String?, Error?) -> Void) { }
func test(_ str: String) -> Bool { return false }

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNRELATED %s
withError { res, err in
  if test("unrelated") {
    print("unrelated")
  } else {
    print("else unrelated")
  }
}
// UNRELATED: convert_params_single.swift
// UNRELATED-NEXT: let res = try await withError()
// UNRELATED-NEXT: if test("unrelated") {
// UNRELATED-NEXT: print("unrelated")
// UNRELATED-NEXT: } else {
// UNRELATED-NEXT: print("else unrelated")
// UNRELATED-NEXT: }

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=BOUND %s
withError { res, err in
  print("before")
  if let bad = err {
    print("got error \(bad)")
    return
  }
  if let str = res {
    print("got result \(str)")
  }
  print("after")
}
// BOUND: do {
// BOUND-NEXT: let str = try await withError()
// BOUND-NEXT: print("before")
// BOUND-NEXT: print("got result \(str)")
// BOUND-NEXT: print("after")
// BOUND-NEXT: } catch let bad {
// BOUND-NEXT: print("got error \(bad)")
// BOUND-NEXT: }

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND-ERR %s
withError { res, err in
  print("before")
  guard let str = res else {
    print("got error \(err!)")
    return
  }
  print("got result \(str)")
  print("after")
}
// UNBOUND-ERR: do {
// UNBOUND-ERR-NEXT: let str = try await withError()
// UNBOUND-ERR-NEXT: print("before")
// UNBOUND-ERR-NEXT: print("got result \(str)")
// UNBOUND-ERR-NEXT: print("after")
// UNBOUND-ERR-NEXT: } catch let err {
// UNBOUND-ERR-NEXT: print("got error \(err)")
// UNBOUND-ERR-NEXT: }

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=BOUND %s
withError { res, err in
  print("before")
  if let bad = err {
    print("got error \(bad)")
  } else if let str = res {
    print("got result \(str)")
  }
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=BOUND %s
withError { res, err in
  print("before")
  if let bad = err {
    print("got error \(bad)")
    return
  }
  if let str = res {
    print("got result \(str)")
  }
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND-RES %s
withError { res, err in
  print("before")
  if let bad = err {
    print("got error \(bad)")
    return
  }
  print("got result \(res!)")
  print("after")
}
// UNBOUND-RES: do {
// UNBOUND-RES-NEXT: let res = try await withError()
// UNBOUND-RES-NEXT: print("before")
// UNBOUND-RES-NEXT: print("got result \(res)")
// UNBOUND-RES-NEXT: print("after")
// UNBOUND-RES-NEXT: } catch let bad {
// UNBOUND-RES-NEXT: print("got error \(bad)")
// UNBOUND-RES-NEXT: }

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND-ERR %s
withError { res, err in
  print("before")
  if let str = res {
    print("got result \(str)")
    print("after")
    return
  }
  print("got error \(err!)")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND-RES %s
withError { res, err in
  print("before")
  if let bad = err {
    print("got error \(bad)")
  } else {
    print("got result \(res!)")
  }
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND-ERR %s
withError { res, err in
  print("before")
  if let str = res {
    print("got result \(str)")
  } else {
    print("got error \(err!)")
  }
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND %s
withError { res, err in
  print("before")
  if err != nil {
    print("got error \(err!)")
    return
  }
  print("got result \(res!)")
  print("after")
}
// UNBOUND: do {
// UNBOUND-NEXT: let res = try await withError()
// UNBOUND-NEXT: print("before")
// UNBOUND-NEXT: print("got result \(res)")
// UNBOUND-NEXT: print("after")
// UNBOUND-NEXT: } catch let err {
// UNBOUND-NEXT: print("got error \(err)")
// UNBOUND-NEXT: }

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND %s
withError { res, err in
  print("before")
  if res != nil {
    print("got result \(res!)")
    print("after")
    return
  }
  print("got error \(err!)")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND %s
withError { res, err in
  print("before")
  if err != nil {
    print("got error \(err!)")
  } else {
    print("got result \(res!)")
  }
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND %s
withError { res, err in
  print("before")
  if res != nil {
    print("got result \(res!)")
  } else {
    print("got error \(err!)")
  }
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND %s
withError { res, err in
  print("before")
  if err == nil {
    print("got result \(res!)")
  } else {
    print("got error \(err!)")
  }
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND %s
withError { res, err in
  print("before")
  if res == nil {
    print("got error \(err!)")
  } else {
    print("got result \(res!)")
  }
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNHANDLEDNESTED %s
withError { res, err in
  print("before")
  if let bad = err {
    print("got error \(bad)")
  } else {
    if let str = res {
      print("got result \(str)")
    }
  }
  print("after")
}
// UNHANDLEDNESTED: do {
// UNHANDLEDNESTED-NEXT: let res = try await withError()
// UNHANDLEDNESTED-NEXT: print("before")
// UNHANDLEDNESTED-NEXT: if let str = <#res#> {
// UNHANDLEDNESTED-NEXT: print("got result \(str)")
// UNHANDLEDNESTED-NEXT: }
// UNHANDLEDNESTED-NEXT: print("after")
// UNHANDLEDNESTED-NEXT: } catch let bad {
// UNHANDLEDNESTED-NEXT: print("got error \(bad)")
// UNHANDLEDNESTED-NEXT: }

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=NOERR %s
withError { res, err in
  print("before")
  if let str = res {
    print("got result \(str)")
  }
  print("after")
}
// NOERR: convert_params_single.swift
// NOERR-NEXT: let str = try await withError()
// NOERR-NEXT: print("before")
// NOERR-NEXT: print("got result \(str)")
// NOERR-NEXT: print("after")
// NOERR-NOT: }

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=NORES %s
withError { res, err in
  print("before")
  if let bad = err {
    print("got error \(bad)")
  }
  print("after")
}
// NORES: do {
// NORES-NEXT: let res = try await withError()
// NORES-NEXT: print("before")
// NORES-NEXT: print("after")
// NORES-NEXT: } catch let bad {
// NORES-NEXT: print("got error \(bad)")
// NORES-NEXT: }

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND %s
withError { res, err in
  print("before")
  if res != nil && err == nil {
    print("got result \(res!)")
  } else {
    print("got error \(err!)")
  }
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNKNOWN-COND %s
withError { res, err in
  print("before")
  if res != nil && test(res!) {
    print("got result \(res!)")
  }
  print("after")
}
// UNKNOWN-COND: convert_params_single.swift
// UNKNOWN-COND-NEXT: let res = try await withError()
// UNKNOWN-COND-NEXT: print("before")
// UNKNOWN-COND-NEXT: if <#res#> != nil && test(res) {
// UNKNOWN-COND-NEXT: print("got result \(res)")
// UNKNOWN-COND-NEXT: }
// UNKNOWN-COND-NEXT: print("after")

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNKNOWN-CONDELSE %s
withError { res, err in
  print("before")
  if res != nil && test(res!) {
    print("got result \(res!)")
  } else {
    print("bad")
  }
  print("after")
}
// UNKNOWN-CONDELSE: var res: String? = nil
// UNKNOWN-CONDELSE-NEXT: var err: Error? = nil
// UNKNOWN-CONDELSE-NEXT: do {
// UNKNOWN-CONDELSE-NEXT: res = try await withError()
// UNKNOWN-CONDELSE-NEXT: } catch {
// UNKNOWN-CONDELSE-NEXT: err = error
// UNKNOWN-CONDELSE-NEXT: }
// UNKNOWN-CONDELSE-EMPTY:
// UNKNOWN-CONDELSE-NEXT: print("before")
// UNKNOWN-CONDELSE-NEXT: if res != nil && test(res!) {
// UNKNOWN-CONDELSE-NEXT: print("got result \(res!)")
// UNKNOWN-CONDELSE-NEXT: } else {
// UNKNOWN-CONDELSE-NEXT: print("bad")
// UNKNOWN-CONDELSE-NEXT: }
// UNKNOWN-CONDELSE-NEXT: print("after")

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=MULTIBIND %s
withError { res, err in
  print("before")
  if let str = res {
    print("got result \(str)")
  }
  if let str2 = res {
    print("got result \(str2)")
  }
  print("after")
}
// MULTIBIND: var res: String? = nil
// MULTIBIND-NEXT: var err: Error? = nil
// MULTIBIND-NEXT: do {
// MULTIBIND-NEXT: res = try await withError()
// MULTIBIND-NEXT: } catch {
// MULTIBIND-NEXT: err = error
// MULTIBIND-NEXT: }
// MULTIBIND-EMPTY:
// MULTIBIND-NEXT: print("before")
// MULTIBIND-NEXT: if let str = res {
// MULTIBIND-NEXT: print("got result \(str)")
// MULTIBIND-NEXT: }
// MULTIBIND-NEXT: if let str2 = res {
// MULTIBIND-NEXT: print("got result \(str2)")
// MULTIBIND-NEXT: }
// MULTIBIND-NEXT: print("after")

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=NESTEDRET %s
withError { res, err in
  print("before")
  if let str = res {
    if test(str) {
      return
    }
    print("got result \(str)")
  }
  print("after")
}
// NESTEDRET: convert_params_single.swift
// NESTEDRET-NEXT: let str = try await withError()
// NESTEDRET-NEXT: print("before")
// NESTEDRET-NEXT: if test(str) {
// NESTEDRET-NEXT: return
// NESTEDRET-NEXT: }
// NESTEDRET-NEXT: print("got result \(str)")
// NESTEDRET-NEXT: print("after")
// NESTEDRET-NOT: }

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND-ERR %s
withError { res, err in
  print("before")
  guard let str = res, err == nil else {
    print("got error \(err!)")
    return
  }
  print("got result \(str)")
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND %s
withError { res, err in
  print("before")
  guard res != nil else {
    print("got error \(err!)")
    return
  }
  print("got result \(res!)")
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND %s
withError { res, err in
  print("before")
  guard err == nil else {
    print("got error \(err!)")
    return
  }
  print("got result \(res!)")
  print("after")
}

// RUN: %refactor -convert-call-to-async-alternative -dump-text -source-filename %s -pos=%(line+1):3 | %FileCheck -check-prefix=UNBOUND %s
withError { res, err in
  print("before")
  guard res != nil && err == nil else {
    print("got error \(err!)")
    return
  }
  print("got result \(res!)")
  print("after")
}
