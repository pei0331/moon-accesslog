///|
/// One parsed Common or Combined Log Format record.
pub struct AccessRecord {
  address : String
  timestamp : String
  http_method : String
  path : String
  route : String
  query : String
  protocol : String
  status : Int
  bytes : Int
  referrer : String
  user_agent : String
}

///|
/// Aggregate report for valid and malformed log lines.
pub struct Report {
  mut total_lines : Int
  mut invalid_lines : Int
  mut filtered_lines : Int
  mut requests : Int
  mut total_bytes : Int
  mut query_requests : Int
  status_counts : Map[Int, Int]
  method_counts : Map[String, Int]
  path_counts : Map[String, Int]
  address_counts : Map[String, Int]
  hourly_counts : Map[String, Int]
  route_counts : Map[String, Int]
  user_agent_counts : Map[String, Int]
  referrer_counts : Map[String, Int]
  query_key_counts : Map[String, Int]
  protocol_counts : Map[String, Int]
  route_error_counts : Map[String, Int]
  route_bytes_counts : Map[String, Int]
}

///|
/// Parse one Common or Combined Log Format record.
pub fn parse_line(line : String) -> AccessRecord? {
  if !balanced_delimiters(line) {
    return None
  }
  let tokens = tokenize(line)
  if tokens.length() < 7 {
    return None
  }
  let timestamp = tokens[3]
  if timestamp.length() < 2 {
    return None
  }
  let request = tokens[4]
  let parts = split_request(request)
  if parts.length() < 3 {
    return None
  }
  if parts[0] == "" || !parts[2].has_prefix("HTTP/") {
    return None
  }
  let status = @string.parse_int(tokens[5]) catch { _ => return None }
  if status < 100 || status > 599 {
    return None
  }
  let byte_count = if tokens.length() > 6 && tokens[6] != "-" {
    let parsed = @string.parse_int(tokens[6]) catch { _ => return None }
    if parsed < 0 {
      return None
    }
    parsed
  } else {
    0
  }
  let referrer = if tokens.length() > 7 { tokens[7] } else { "-" }
  let user_agent = if tokens.length() > 8 { tokens[8] } else { "-" }
  let target = parts[1]
  let (route, query) = split_query(target)
  Some(AccessRecord::{
    address: tokens[0],
    timestamp,
    http_method: parts[0],
    path: target,
    route,
    query,
    protocol: parts[2],
    status,
    bytes: byte_count,
    referrer,
    user_agent,
  })
}

///|
/// Analyze newline-separated Common or Combined Log Format input.
pub fn analyze(source : String) -> Report {
  analyze_with_options(source, AnalyzeOptions::new())
}

///|
/// Render the report as stable plain text.
pub fn Report::to_text(self : Report, top? : Int = 10) -> String {
  let limit = if top < 0 { 0 } else { top }
  let mut out = "Access log summary\n"
  out = out +
    "Lines: \{self.total_lines} (valid: \{self.requests}, invalid: \{self.invalid_lines}, filtered: \{self.filtered_lines})\n"
  out = out + "Transferred bytes: \{self.total_bytes}\n"
  out = out +
    "Requests with query: \{self.query_requests} (\{self.query_request_percent()}%)\n"
  out = out +
    "Error requests: \{self.error_requests()} (\{self.error_rate_percent()}%)\n"
  out = out +
    "Success requests: \{self.success_requests()} (\{self.success_rate_percent()}%)\n"
  out = out + "Client errors (4xx): \{self.client_error_requests()}\n"
  out = out + "Server errors (5xx): \{self.server_error_requests()}\n"
  out = out + "Unique paths: \{self.unique_path_count()}\n"
  out = out + "\nStatus codes\n"
  out = out + render_int_counts(self.status_counts)
  out = out + "\nMethods\n"
  out = out + render_string_counts(self.method_counts, limit)
  out = out + "\nTop paths\n"
  out = out + render_string_counts(self.path_counts, limit)
  out = out + "\nTop routes (query excluded)\n"
  out = out + render_string_counts(self.route_counts, limit)
  out = out + "\nTop client addresses\n"
  out = out + render_string_counts(self.address_counts, limit)
  out = out + "\nTop user agents\n"
  out = out + render_string_counts(self.user_agent_counts, limit)
  out = out + "\nTop referrers\n"
  out = out + render_string_counts(self.referrer_counts, limit)
  out = out + "\nRequests by UTC hour\n"
  out = out + render_string_counts(self.hourly_counts, 24)
  out
}

///|
/// Render the report as deterministic JSON for archival and CI pipelines.
pub fn Report::to_json(self : Report) -> String {
  let mut out = "{\"total_lines\":\{self.total_lines},\"invalid_lines\":\{self.invalid_lines},\"filtered_lines\":\{self.filtered_lines},\"requests\":\{self.requests},\"query_requests\":\{self.query_requests},\"total_bytes\":\{self.total_bytes},\"error_requests\":\{self.error_requests()},\"error_rate_percent\":\{self.error_rate_percent()},\"success_requests\":\{self.success_requests()},\"success_rate_percent\":\{self.success_rate_percent()},\"client_error_requests\":\{self.client_error_requests()},\"server_error_requests\":\{self.server_error_requests()},\"unique_paths\":\{self.unique_path_count()}"
  out = out + ",\"status_counts\":" + render_json_int_counts(self.status_counts)
  out = out +
    ",\"method_counts\":" +
    render_json_string_counts(self.method_counts)
  out = out + ",\"path_counts\":" + render_json_string_counts(self.path_counts)
  out = out +
    ",\"route_counts\":" +
    render_json_string_counts(self.route_counts)
  out = out +
    ",\"status_class_counts\":" +
    render_json_string_counts(self.status_class_counts())
  out = out +
    ",\"address_counts\":" +
    render_json_string_counts(self.address_counts)
  out = out +
    ",\"hourly_counts\":" +
    render_json_string_counts(self.hourly_counts)
  out = out +
    ",\"user_agent_counts\":" +
    render_json_string_counts(self.user_agent_counts)
  out = out +
    ",\"referrer_counts\":" +
    render_json_string_counts(self.referrer_counts)
  out = out +
    ",\"query_key_counts\":" +
    render_json_string_counts(self.query_key_counts)
  out = out +
    ",\"protocol_counts\":" +
    render_json_string_counts(self.protocol_counts)
  out + "}"
}

///|
/// Render metrics as CSV rows with the columns `metric,key,value`.
pub fn Report::to_csv(self : Report) -> String {
  let mut out = "metric,key,value\n"
  out = out + "summary,total_lines,\{self.total_lines}\n"
  out = out + "summary,invalid_lines,\{self.invalid_lines}\n"
  out = out + "summary,filtered_lines,\{self.filtered_lines}\n"
  out = out + "summary,requests,\{self.requests}\n"
  out = out + "summary,total_bytes,\{self.total_bytes}\n"
  out = out + "summary,query_requests,\{self.query_requests}\n"
  out = out + "summary,error_requests,\{self.error_requests()}\n"
  out = out + "summary,error_rate_percent,\{self.error_rate_percent()}\n"
  out = out + "summary,success_requests,\{self.success_requests()}\n"
  out = out + "summary,success_rate_percent,\{self.success_rate_percent()}\n"
  out = out + "summary,client_error_requests,\{self.client_error_requests()}\n"
  out = out + "summary,server_error_requests,\{self.server_error_requests()}\n"
  out = out + "summary,unique_paths,\{self.unique_path_count()}\n"
  out = out + render_csv_int_counts("status", self.status_counts)
  out = out +
    render_csv_string_counts("status_class", self.status_class_counts())
  out = out + render_csv_string_counts("method", self.method_counts)
  out = out + render_csv_string_counts("path", self.path_counts)
  out = out + render_csv_string_counts("route", self.route_counts)
  out = out + render_csv_string_counts("address", self.address_counts)
  out = out + render_csv_string_counts("user_agent", self.user_agent_counts)
  out = out + render_csv_string_counts("referrer", self.referrer_counts)
  out = out + render_csv_string_counts("query_key", self.query_key_counts)
  out = out + render_csv_string_counts("protocol", self.protocol_counts)
  out = out + render_csv_string_counts("route_error", self.route_error_counts)
  out = out + render_csv_string_counts("route_bytes", self.route_bytes_counts)
  out + render_csv_string_counts("utc_hour", self.hourly_counts)
}

///|
/// Number of valid requests with a 4xx or 5xx status code.
pub fn Report::error_requests(self : Report) -> Int {
  let mut total = 0
  for status, count in self.status_counts {
    if status >= 400 {
      total += count
    }
  }
  total
}

///|
/// Error percentage rounded down to a whole number.
pub fn Report::error_rate_percent(self : Report) -> Int {
  if self.requests == 0 {
    0
  } else {
    self.error_requests() * 100 / self.requests
  }
}

///|
/// Number of distinct request paths in valid records.
pub fn Report::unique_path_count(self : Report) -> Int {
  let mut total = 0
  for _, _ in self.path_counts {
    total += 1
  }
  total
}

///|
fn tokenize(line : String) -> Array[String] {
  let chars = line.to_array()
  let tokens : Array[String] = []
  let mut i = 0
  while i < chars.length() {
    while i < chars.length() && chars[i].is_ascii_whitespace() {
      i += 1
    }
    if i < chars.length() {
      let quote = chars[i]
      if quote == '"' || quote == '[' {
        let close = if quote == '[' { ']' } else { '"' }
        i += 1
        let start = i
        while i < chars.length() && chars[i] != close {
          if chars[i] == '\\' && i + 1 < chars.length() {
            i += 2
          } else {
            i += 1
          }
        }
        tokens.push(String::from_array(chars[start:i]))
        if i < chars.length() {
          i += 1
        }
      } else {
        let start = i
        while i < chars.length() && !chars[i].is_ascii_whitespace() {
          i += 1
        }
        tokens.push(String::from_array(chars[start:i]))
      }
    }
  }
  tokens
}

///|
/// Split a quoted request line while tolerating repeated whitespace.
fn split_request(request : String) -> Array[String] {
  let chars = request.to_array()
  let parts : Array[String] = []
  let mut start = 0
  let mut i = 0
  while i < chars.length() {
    while i < chars.length() && chars[i].is_ascii_whitespace() {
      i += 1
    }
    start = i
    while i < chars.length() && !chars[i].is_ascii_whitespace() {
      i += 1
    }
    if start < i {
      parts.push(String::from_array(chars[start:i]))
    }
  }
  parts
}

///|
/// Reject records with an unterminated quoted or bracketed field.
fn balanced_delimiters(line : String) -> Bool {
  let chars = line.to_array()
  let mut quote_open = false
  let mut bracket_open = false
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '\\' && i + 1 < chars.length() {
      i += 2
    } else if chars[i] == '"' {
      quote_open = !quote_open
      i += 1
    } else if !quote_open && chars[i] == '[' {
      if bracket_open {
        return false
      }
      bracket_open = true
      i += 1
    } else if !quote_open && chars[i] == ']' {
      if !bracket_open {
        return false
      }
      bracket_open = false
      i += 1
    } else {
      i += 1
    }
  }
  !quote_open && !bracket_open
}

///|
fn hour_bucket(timestamp : String) -> String {
  let chars = timestamp.to_array()
  let mut colon = 0
  while colon < chars.length() && chars[colon] != ':' {
    colon += 1
  }
  if colon + 3 > chars.length() {
    return ""
  }
  let day = String::from_array(chars[0:colon])
  let hour = String::from_array(chars[colon + 1:colon + 3])
  "\{day}:\{hour}:00"
}

///|
/// Split a request target into its route and query components.
fn split_query(target : String) -> (String, String) {
  let chars = target.to_array()
  let mut index = 0
  while index < chars.length() && chars[index] != '?' {
    index += 1
  }
  if index == chars.length() {
    (target, "")
  } else {
    (String::from_array(chars[0:index]), String::from_array(chars[index + 1:]))
  }
}

///|
fn[K : Eq + Hash] increment(counts : Map[K, Int], key : K) -> Unit {
  let current = match counts.get(key) {
    Some(value) => value
    None => 0
  }
  counts[key] = current + 1
}

///|
/// Add an arbitrary amount to a grouped integer counter.
fn[K : Eq + Hash] increment_by(
  counts : Map[K, Int],
  key : K,
  amount : Int,
) -> Unit {
  let current = match counts.get(key) {
    Some(value) => value
    None => 0
  }
  counts[key] = current + amount
}

///|
fn render_int_counts(counts : Map[Int, Int]) -> String {
  let entries : Array[(Int, Int)] = []
  for key, value in counts {
    entries.push((key, value))
  }
  entries.sort_by((a, b) => {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  let mut out = ""
  for _, entry in entries {
    out = out + "  \{entry.0}: \{entry.1}\n"
  }
  out
}

///|
fn render_string_counts(counts : Map[String, Int], limit : Int) -> String {
  let entries : Array[(String, Int)] = []
  for key, value in counts {
    entries.push((key, value))
  }
  entries.sort_by(fn(a, b) {
    if a.1 > b.1 {
      -1
    } else if a.1 < b.1 {
      1
    } else {
      a.0.compare(b.0)
    }
  })
  let mut out = ""
  let mut index = 0
  for _, entry in entries {
    if index < limit {
      out = out + "  \{entry.0}: \{entry.1}\n"
    }
    index += 1
  }
  if entries.is_empty() {
    out + "  (none)\n"
  } else {
    out
  }
}

///|
fn render_json_int_counts(counts : Map[Int, Int]) -> String {
  let entries : Array[(Int, Int)] = []
  for key, value in counts {
    entries.push((key, value))
  }
  entries.sort_by((a, b) => {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  let mut out = "{"
  for i, entry in entries {
    if i > 0 {
      out = out + ","
    }
    out = out + "\"\{entry.0}\":\{entry.1}"
  }
  out + "}"
}

///|
fn render_json_string_counts(counts : Map[String, Int]) -> String {
  let entries : Array[(String, Int)] = []
  for key, value in counts {
    entries.push((key, value))
  }
  entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  let mut out = "{"
  for i, entry in entries {
    if i > 0 {
      out = out + ","
    }
    out = out + "\"" + json_escape(entry.0) + "\":" + entry.1.to_string()
  }
  out + "}"
}

///|
fn json_escape(value : String) -> String {
  let mut out = ""
  for ch in value.to_array() {
    match ch {
      '"' => out = out + "\\\""
      '\\' => out = out + "\\\\"
      '\n' => out = out + "\\n"
      '\r' => out = out + "\\r"
      '\t' => out = out + "\\t"
      _ => out = out + ch.to_string()
    }
  }
  out
}

///|
fn csv_escape(value : String) -> String {
  let mut needs_quotes = false
  for ch in value.to_array() {
    if ch == ',' || ch == '"' || ch == '\n' || ch == '\r' {
      needs_quotes = true
    }
  }
  let mut escaped = ""
  for ch in value.to_array() {
    if ch == '"' {
      escaped = escaped + "\"\""
    } else {
      escaped = escaped + ch.to_string()
    }
  }
  if needs_quotes {
    "\"" + escaped + "\""
  } else {
    escaped
  }
}

///|
fn render_csv_int_counts(metric : String, counts : Map[Int, Int]) -> String {
  let entries : Array[(Int, Int)] = []
  for key, value in counts {
    entries.push((key, value))
  }
  entries.sort_by((a, b) => {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  let mut out = ""
  for _, entry in entries {
    out = out +
      metric +
      "," +
      entry.0.to_string() +
      "," +
      entry.1.to_string() +
      "\n"
  }
  out
}

///|
fn render_csv_string_counts(
  metric : String,
  counts : Map[String, Int],
) -> String {
  let entries : Array[(String, Int)] = []
  for key, value in counts {
    entries.push((key, value))
  }
  entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  let mut out = ""
  for _, entry in entries {
    out = out +
      metric +
      "," +
      csv_escape(entry.0) +
      "," +
      entry.1.to_string() +
      "\n"
  }
  out
}
