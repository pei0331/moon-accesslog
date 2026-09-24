///|
fn main {
  let args = @env.args()
  let mut top = 10
  let mut json = false
  let mut path : String? = None
  let mut i = 1
  while i < args.length() {
    if args[i] == "--top" {
      if i + 1 >= args.length() {
        fail("missing count after --top")
      }
      top = @string.parse_int(args[i + 1]) catch {
        _ => {
          fail("--top expects a non-negative integer")
          0
        }
      }
      if top < 0 {
        fail("--top expects a non-negative integer")
      }
      i += 2
    } else if args[i] == "--json" {
      json = true
      i += 1
    } else if args[i] == "--help" || args[i] == "-h" {
      println("Usage: moon-accesslog [--top N] [--json] <access.log>")
      return
    } else if path is None {
      path = Some(args[i])
      i += 1
    } else {
      fail("unexpected argument '\{args[i]}'")
    }
  }
  match path {
    Some(input) => {
      let source = match read_file(input) {
        Some(value) => value
        None => {
          fail("cannot read '\{input}'")
          ""
        }
      }
      let report = @accesslog.analyze(source)
      if json {
        println(report.to_json())
      } else {
        println(report.to_text(top~))
      }
    }
    None => fail("Usage: moon-accesslog [--top N] [--json] <access.log>")
  }
}

///|
fn fail(message : String) -> Unit {
  println("error: \{message}")
  abort("moon-accesslog: \{message}")
}
