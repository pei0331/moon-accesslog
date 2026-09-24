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
