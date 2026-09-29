///|
test "parse combined log with quoted request and user agent" {
  let record = parse_line(
    "127.0.0.1 - alice [10/Oct/2000:13:55:36 +0000] \"GET /index.html HTTP/1.1\" 200 2326 \"https://example.test/\" \"Mozilla/5.0 (X11; Linux x86_64)\"",
  )
  assert_true(record is Some(_))
  match record {
    Some(value) => {
      assert_eq(value.http_method, "GET")
      assert_eq(value.path, "/index.html")
      assert_eq(value.status, 200)
      assert_eq(value.bytes, 2326)
      assert_eq(value.user_agent, "Mozilla/5.0 (X11; Linux x86_64)")
    }
    None => abort("expected record")
  }
}

///|
test "reject malformed access log lines" {
  assert_true(parse_line("not a log") is None)
  assert_true(
    parse_line("127.0.0.1 - - [bad] \"GET / HTTP/1.1\" nope 10") is None,
  )
}

///|
test "aggregate status method paths bytes and hours" {
  let source = "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /a HTTP/1.1\" 200 100\n127.0.0.2 - - [10/Oct/2000:13:56:36 +0000] \"GET /a HTTP/1.1\" 200 50\n127.0.0.1 - - [10/Oct/2000:14:01:00 +0000] \"POST /b HTTP/1.1\" 404 7\nbad line"
  let report = analyze(source)
  assert_eq(report.requests, 3)
  assert_eq(report.invalid_lines, 1)
  assert_eq(report.total_bytes, 157)
  assert_eq(report.error_requests(), 1)
  assert_eq(report.error_rate_percent(), 33)
  assert_eq(report.unique_path_count(), 2)
  assert_eq(report.path_counts.get("/a"), Some(2))
  assert_eq(report.status_counts.get(404), Some(1))
  assert_eq(report.hourly_counts.get("10/Oct/2000:13:00"), Some(2))
  assert_true(report.to_text(top=1).contains("Transferred bytes: 157"))
}

///|
test "common format defaults optional fields" {
  let record = parse_line(
    "192.0.2.1 - - [10/Oct/2000:13:55:36 +0000] \"HEAD /health HTTP/1.0\" 204 -",
  )
  match record {
    Some(value) => {
      assert_eq(value.bytes, 0)
      assert_eq(value.referrer, "-")
      assert_eq(value.user_agent, "-")
    }
    None => abort("expected record")
  }
}

///|
test "render deterministic JSON with escaped keys" {
  let report = analyze(
    "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /quote-path HTTP/1.1\" 200 3",
  )
  let json = report.to_json()
  assert_true(json.contains("\"requests\":1"))
  assert_true(json.contains("\"total_bytes\":3"))
  assert_true(json.contains("\"error_requests\":0"))
  assert_true(json.contains("\"unique_paths\":1"))
  assert_true(json.contains("\"/quote-path\":1"))
}

///|
test "render CSV metrics with a header" {
  let report = analyze(
    "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /a HTTP/1.1\" 200 3",
  )
  let csv = report.to_csv()
  assert_true(csv.has_prefix("metric,key,value\n"))
  assert_true(csv.contains("summary,total_bytes,3\n"))
  assert_true(csv.contains("path,/a,1\n"))
}

///|
test "split request query from route and count both dimensions" {
  let record = parse_line(
    "192.0.2.9 - - [10/Oct/2000:13:55:36 +0000] \"GET /search?q=moon&sort=new HTTP/1.1\" 200 12",
  )
  match record {
    Some(value) => {
      assert_eq(value.path, "/search?q=moon&sort=new")
      assert_eq(value.route, "/search")
      assert_eq(value.query, "q=moon&sort=new")
    }
    None => abort("expected record")
  }
  let report = analyze(
    "192.0.2.9 - - [10/Oct/2000:13:55:36 +0000] \"GET /search?q=moon HTTP/1.1\" 200 12\n192.0.2.9 - - [10/Oct/2000:13:56:36 +0000] \"GET /search?q=bit HTTP/1.1\" 200 8",
  )
  assert_eq(report.path_counts.get("/search?q=moon"), Some(1))
  assert_eq(report.route_counts.get("/search"), Some(2))
}

///|
test "filter options count excluded valid records separately" {
  let source = "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /api/a HTTP/1.1\" 200 10\n127.0.0.2 - - [10/Oct/2000:13:56:36 +0000] \"POST /api/b HTTP/1.1\" 201 20\n127.0.0.1 - - [10/Oct/2000:13:57:36 +0000] \"GET /health HTTP/1.1\" 503 4\nbad line"
  let options = AnalyzeOptions::from(
    Some("GET"),
    Some("/api"),
    Some("127.0.0.1"),
    Some(200),
    Some(299),
  )
  let report = analyze_with_options(source, options)
  assert_eq(report.total_lines, 4)
  assert_eq(report.invalid_lines, 1)
  assert_eq(report.filtered_lines, 2)
  assert_eq(report.requests, 1)
  assert_eq(report.total_bytes, 10)
}

///|
test "incremental analyzer matches batch analysis" {
  let lines : Array[String] = [
    "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /a HTTP/1.1\" 200 10", "127.0.0.2 - - [10/Oct/2000:14:01:36 +0000] \"POST /b HTTP/1.1\" 500 20",
    "not valid",
  ]
  let options = AnalyzeOptions::new()
  let incremental = Analyzer::new(options)
    .push(lines[0])
    .push(lines[1])
    .push(lines[2])
    .finish()
  let batch = analyze_lines(lines, AnalyzeOptions::new())
  assert_eq(incremental.requests, batch.requests)
  assert_eq(incremental.invalid_lines, batch.invalid_lines)
  assert_eq(incremental.total_bytes, batch.total_bytes)
  assert_eq(incremental.status_counts.get(500), Some(1))
}

///|
test "status metrics and top results are deterministic" {
  let report = analyze(
    "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /z HTTP/1.1\" 200 1\n127.0.0.1 - - [10/Oct/2000:13:56:36 +0000] \"GET /a HTTP/1.1\" 404 2\n127.0.0.2 - - [10/Oct/2000:13:57:36 +0000] \"GET /a HTTP/1.1\" 503 3\n127.0.0.2 - - [10/Oct/2000:13:58:36 +0000] \"GET /z HTTP/1.1\" 301 4",
  )
  assert_eq(report.success_requests(), 2)
  assert_eq(report.client_error_requests(), 1)
  assert_eq(report.server_error_requests(), 1)
  assert_eq(report.success_rate_percent(), 50)
  assert_eq(report.status_class_counts().get("5xx"), Some(1))
  let top = report.top_paths(2)
  assert_eq(top[0], ("/a", 2))
  assert_eq(top[1], ("/z", 2))
  let routes = report.top_routes(1)
  assert_eq(routes[0], ("/a", 2))
}

///|
test "machine outputs include filtering and health metrics" {
  let report = analyze(
    "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /a HTTP/1.1\" 200 3",
  )
  assert_true(report.to_json().contains("\"filtered_lines\":0"))
  assert_true(report.to_json().contains("\"success_rate_percent\":100"))
  assert_true(report.to_json().contains("\"success_requests\":1"))
  assert_true(report.to_json().contains("\"route_counts\""))
  assert_true(report.to_json().contains("\"status_class_counts\":{\"2xx\":1}"))
  assert_true(report.to_csv().contains("summary,success_rate_percent,100\n"))
  assert_true(report.to_csv().contains("status_class,2xx,1\n"))
  assert_true(report.to_text().contains("Top routes (query excluded)"))
}

///|
test "parser accepts repeated request whitespace" {
  let record = parse_line(
    "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET   /spaced   HTTP/1.1\" 200 1",
  )
  match record {
    Some(value) => {
      assert_eq(value.http_method, "GET")
      assert_eq(value.path, "/spaced")
      assert_eq(value.protocol, "HTTP/1.1")
    }
    None => abort("expected repeated whitespace to parse")
  }
}

///|
test "parser rejects unterminated fields" {
  assert_true(
    parse_line(
      "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /broken HTTP/1.1 200 1",
    )
    is None,
  )
  assert_true(
    parse_line(
      "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000 \"GET /broken HTTP/1.1\" 200 1",
    )
    is None,
  )
}

///|
test "reports merge without losing counters" {
  let first = analyze(
    "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /a HTTP/1.1\" 200 10\nbad",
  )
  let second = analyze(
    "127.0.0.2 - - [10/Oct/2000:14:01:36 +0000] \"POST /b HTTP/1.1\" 500 20",
  )
  let merged = first.merge(second)
  assert_eq(merged.total_lines, 3)
  assert_eq(merged.invalid_lines, 1)
  assert_eq(merged.requests, 2)
  assert_eq(merged.total_bytes, 30)
  assert_eq(merged.status_counts.get(200), Some(1))
  assert_eq(merged.status_counts.get(500), Some(1))
}

///|
test "health budget uses inclusive error percentage" {
  let report = analyze(
    "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /a HTTP/1.1\" 200 1\n127.0.0.1 - - [10/Oct/2000:13:56:36 +0000] \"GET /b HTTP/1.1\" 500 1",
  )
  assert_true(report.is_healthy(50))
  assert_true(!report.is_healthy(49))
}

///|
test "hour prefix filter keeps matching UTC buckets" {
  let source = "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /a HTTP/1.1\" 200 1\n127.0.0.1 - - [10/Oct/2000:14:01:36 +0000] \"GET /b HTTP/1.1\" 200 2"
  let options = AnalyzeOptions::new().with_hour_prefix(Some("10/Oct/2000:13"))
  let report = analyze_with_options(source, options)
  assert_eq(report.requests, 1)
  assert_eq(report.filtered_lines, 1)
  assert_eq(report.path_counts.get("/a"), Some(1))
}

///|
test "reject invalid status bytes and protocol" {
  assert_true(
    parse_line(
      "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /a FTP/1.0\" 200 1",
    )
    is None,
  )
  assert_true(
    parse_line(
      "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /a HTTP/1.1\" 99 1",
    )
    is None,
  )
  assert_true(
    parse_line(
      "127.0.0.1 - - [10/Oct/2000:13:55:36 +0000] \"GET /a HTTP/1.1\" 200 -1",
    )
    is None,
  )
}
