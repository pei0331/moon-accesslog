///|
test "unchanged interface is compatible" {
  let source = "package demo:api; interface math { add: func(a: u32, b: u32) -> u32; }"
  let old = parse(source)
  let new = parse(source)
  let report = compare(old, new)
  assert_false(report.has_breaking())
  assert_eq(report.changes.length(), 0)
}

///|
test "removed and changed declarations are breaking" {
  let old = parse(
    "package demo:api; interface math { add: func(a: u32) -> u32; sub: func(a: u32) -> u32; }",
  )
  let new = parse(
    "package demo:api; interface math { add: func(a: u64) -> u32; }",
  )
  let report = compare(old, new)
  assert_true(report.has_breaking())
  assert_eq(report.changes.length(), 2)
}

///|
test "added declarations are compatible additions" {
  let old = parse(
    "package demo:api; interface math { add: func(a: u32) -> u32; }",
  )
  let new = parse(
    "package demo:api; interface math { add: func(a: u32) -> u32; sub: func(a: u32) -> u32; }",
  )
  let report = compare(old, new)
  assert_false(report.has_breaking())
  assert_eq(report.changes.length(), 1)
  assert_true(report.to_string().contains("ADDITIVE"))
}

///|
test "world import and export changes are detected" {
  let old = parse(
    "package demo:api; world app { import log: func(message: string); export run: func(); }",
  )
  let new = parse(
    "package demo:api; world app { import log: func(message: string); export start: func(); }",
  )
  let report = compare(old, new)
  assert_true(report.has_breaking())
  assert_eq(report.changes.length(), 2)
}
