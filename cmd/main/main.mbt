///|
fn main {
  let args = @env.args()
  let strict = args.length() == 4 && args[1] == "--strict"
  let offset = if strict { 1 } else { 0 }
  if args.length() != 3 + offset {
    println("Usage: moon-wit-compat [--strict] <old.wit> <new.wit>")
    abort("usage error")
  }
  let old_path = args[1 + offset]
  let new_path = args[2 + offset]
  let old_source = read_or_fail(old_path)
  let new_source = read_or_fail(new_path)
  let old_package = parse_or_fail(old_path, old_source)
  let new_package = parse_or_fail(new_path, new_source)
  let report = @compat.compare(old_package, new_package)
  println(report.to_string())
  if strict && report.has_breaking() {
    abort("breaking WIT changes detected")
  }
}

///|
fn read_or_fail(path : String) -> String {
  match read_file(path) {
    Some(content) => content
    None => {
      println("error: cannot read '\{path}'")
      abort("read error")
    }
  }
}

///|
fn parse_or_fail(path : String, source : String) -> @compat.WitPackage {
  @compat.parse(source) catch {
    err => {
      println("error: invalid WIT in '\{path}': \{err.to_string()}")
      abort("parse error")
    }
  }
}
