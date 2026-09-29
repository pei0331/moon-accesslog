///|
fn main {
  let args = @env.args()
  let mut top = 10
  let mut json = false
  let mut csv = false
  let mut prometheus = false
  let mut markdown = false
  let mut ndjson = false
  let mut path : String? = None
  let mut http_method : String? = None
  let mut path_prefix : String? = None
  let mut address : String? = None
  let mut status_min : Int? = None
  let mut status_max : Int? = None
  let mut max_error_rate : Int? = None
  let mut hour_prefix : String? = None
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
      if csv {
        fail("--json and --csv cannot be combined")
      }
      json = true
      i += 1
    } else if args[i] == "--csv" {
      if json || prometheus || markdown || ndjson {
        fail("machine-readable output flags cannot be combined")
      }
      csv = true
      i += 1
    } else if args[i] == "--prometheus" {
      if json || csv || markdown || ndjson {
        fail("machine-readable output flags cannot be combined")
      }
      prometheus = true
      i += 1
    } else if args[i] == "--markdown" {
      if json || csv || prometheus || ndjson {
        fail("machine-readable output flags cannot be combined")
      }
      markdown = true
      i += 1
    } else if args[i] == "--ndjson" {
      if json || csv || prometheus || markdown {
        fail("machine-readable output flags cannot be combined")
      }
      ndjson = true
      i += 1
    } else if args[i] == "--method" {
      if i + 1 >= args.length() {
        fail("missing method after --method")
      }
      http_method = Some(args[i + 1])
      i += 2
    } else if args[i] == "--path-prefix" {
      if i + 1 >= args.length() {
        fail("missing prefix after --path-prefix")
      }
      path_prefix = Some(args[i + 1])
      i += 2
    } else if args[i] == "--address" {
      if i + 1 >= args.length() {
        fail("missing address after --address")
      }
      address = Some(args[i + 1])
      i += 2
    } else if args[i] == "--status-min" {
      if i + 1 >= args.length() {
        fail("missing code after --status-min")
      }
      status_min = Some(parse_status(args[i + 1], "--status-min"))
      i += 2
    } else if args[i] == "--status-max" {
      if i + 1 >= args.length() {
        fail("missing code after --status-max")
      }
      status_max = Some(parse_status(args[i + 1], "--status-max"))
      i += 2
    } else if args[i] == "--max-error-rate" {
      if i + 1 >= args.length() {
        fail("missing percentage after --max-error-rate")
      }
      let value = parse_status(args[i + 1], "--max-error-rate")
      if value < 0 || value > 100 {
        fail("--max-error-rate expects a percentage from 0 to 100")
      }
      max_error_rate = Some(value)
      i += 2
    } else if args[i] == "--hour-prefix" {
      if i + 1 >= args.length() {
        fail("missing UTC hour prefix after --hour-prefix")
      }
      hour_prefix = Some(args[i + 1])
      i += 2
    } else if args[i] == "--help" || args[i] == "-h" {
      println("Usage: moon-accesslog [options] <access.log>")
      println("  --top N                 number of rows in text output")
      println("  --json | --csv          select machine-readable output")
      println("  --prometheus            emit Prometheus exposition text")
      println("  --markdown              emit Markdown report")
      println("  --ndjson                emit one metric object per line")
      println("  --method METHOD         keep one HTTP method")
      println("  --path-prefix PREFIX    keep routes under a prefix")
      println("  --address ADDRESS       keep one client address")
      println("  --status-min CODE       inclusive lower status bound")
      println("  --status-max CODE       inclusive upper status bound")
      println("  --max-error-rate N      fail when error percentage exceeds N")
      println(
        "  --hour-prefix PREFIX   keep timestamps under a UTC hour prefix",
      )
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
      let options = @accesslog.AnalyzeOptions::from(
        http_method, path_prefix, address, status_min, status_max,
      )
      let options = options.with_hour_prefix(hour_prefix)
      let report = @accesslog.analyze_with_options(source, options)
      if json {
        println(report.to_json())
      } else if csv {
        println(report.to_csv())
      } else if prometheus {
        println(report.to_prometheus("moon_accesslog"))
      } else if markdown {
        println(report.to_markdown(top~))
      } else if ndjson {
        println(report.to_ndjson())
      } else {
        println(report.to_text(top~))
      }
      match max_error_rate {
        Some(limit) =>
          if !report.is_healthy(limit) {
            fail(
              "error rate \{report.error_rate_percent()}% exceeds limit \{limit}%",
            )
          }
        None => ()
      }
    }
    None => fail("Usage: moon-accesslog [options] <access.log>")
  }
}

///|
fn fail(message : String) -> Unit {
  println("error: \{message}")
  abort("moon-accesslog: \{message}")
}

///|
fn parse_status(value : String, flag : String) -> Int {
  @string.parse_int(value) catch {
    _ => {
      fail("\{flag} expects an integer status code")
      0
    }
  }
}
