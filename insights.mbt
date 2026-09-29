///|
/// A ranked operational finding derived from a report.
pub struct MetricFinding {
  code : String
  severity : String
  message : String
  value : Int
}

///|
/// A compact route-level summary for dashboards and endpoint reviews.
pub struct EndpointSummary {
  route : String
  requests : Int
  errors : Int
  total_bytes : Int
  error_rate_percent : Int
  average_bytes : Int
  depth : Int
}

///|
/// Return the most frequent User-Agent values.
pub fn Report::top_user_agents(
  self : Report,
  limit : Int,
) -> Array[(String, Int)] {
  take_string_counts(self.user_agent_counts, limit)
}

///|
/// Return the most frequent referrer values.
pub fn Report::top_referrers(
  self : Report,
  limit : Int,
) -> Array[(String, Int)] {
  take_string_counts(self.referrer_counts, limit)
}

///|
/// Return query parameter names, independent of their values.
pub fn Report::top_query_keys(
  self : Report,
  limit : Int,
) -> Array[(String, Int)] {
  take_string_counts(self.query_key_counts, limit)
}

///|
/// Return protocol usage counts ranked by frequency.
pub fn Report::top_protocols(
  self : Report,
  limit : Int,
) -> Array[(String, Int)] {
  take_string_counts(self.protocol_counts, limit)
}

///|
/// Count requests by route depth, where `/a/b` has depth two.
pub fn Report::route_depth_counts(self : Report) -> Map[Int, Int] {
  let result : Map[Int, Int] = Map([])
  for route, count in self.route_counts {
    let depth = route_depth(route)
    let current = match result.get(depth) {
      Some(value) => value
      None => 0
    }
    result[depth] = current + count
  }
  result
}

///|
/// Count requests by broad operational class.
pub fn Report::request_class_counts(self : Report) -> Map[String, Int] {
  let result : Map[String, Int] = Map([])
  for status, count in self.status_counts {
    let class = request_class(status)
    let current = match result.get(class) {
      Some(value) => value
      None => 0
    }
    result[class] = current + count
  }
  result
}

///|
/// Return the percentage represented by one status class.
pub fn Report::status_class_percent(self : Report, class : String) -> Int {
  let count = match self.status_class_counts().get(class) {
    Some(value) => value
    None => 0
  }
  if self.requests == 0 {
    0
  } else {
    count * 100 / self.requests
  }
}

///|
/// Return the percentage of requests carrying a query string.
pub fn Report::query_request_percent(self : Report) -> Int {
  let with_query = self.query_requests
  if self.requests == 0 {
    0
  } else {
    with_query * 100 / self.requests
  }
}

///|
/// Return the average response size in bytes.
pub fn Report::average_bytes(self : Report) -> Int {
  if self.requests == 0 {
    0
  } else {
    self.total_bytes / self.requests
  }
}

///|
/// Return the ratio of malformed lines among all non-empty input lines.
pub fn Report::invalid_rate_percent(self : Report) -> Int {
  if self.total_lines == 0 {
    0
  } else {
    self.invalid_lines * 100 / self.total_lines
  }
}

///|
/// Return a stable route-level summary sorted by request count.
pub fn Report::endpoint_summaries(
  self : Report,
  limit : Int,
) -> Array[EndpointSummary] {
  let ranked = take_string_counts(self.route_counts, limit)
  let result : Array[EndpointSummary] = []
  for entry in ranked {
    let route = entry.0
    let requests = entry.1
    let errors = route_error_count(self, route)
    let bytes = route_bytes(self, route)
    let rate = if requests == 0 { 0 } else { errors * 100 / requests }
    result.push(EndpointSummary::{
      route,
      requests,
      errors,
      total_bytes: bytes,
      error_rate_percent: rate,
      average_bytes: if requests == 0 {
        0
      } else {
        bytes / requests
      },
      depth: route_depth(route),
    })
  }
  result
}

///|
/// Find common operational problems in a report.
pub fn Report::findings(self : Report) -> Array[MetricFinding] {
  let result : Array[MetricFinding] = []
  if self.error_rate_percent() >= 20 {
    result.push(MetricFinding::{
      code: "HIGH_ERROR_RATE",
      severity: "error",
      message: "error rate is at least 20 percent",
      value: self.error_rate_percent(),
    })
  }
  if self.server_error_requests() > 0 {
    result.push(MetricFinding::{
      code: "SERVER_ERRORS",
      severity: "error",
      message: "server-side failures were observed",
      value: self.server_error_requests(),
    })
  }
  if self.invalid_rate_percent() >= 5 {
    result.push(MetricFinding::{
      code: "MALFORMED_INPUT",
      severity: "warning",
      message: "at least five percent of lines were malformed",
      value: self.invalid_rate_percent(),
    })
  }
  if self.filtered_lines > 0 {
    result.push(MetricFinding::{
      code: "FILTERED_INPUT",
      severity: "info",
      message: "valid lines were excluded by analysis filters",
      value: self.filtered_lines,
    })
  }
  if self.requests > 0 && self.query_request_percent() >= 80 {
    result.push(MetricFinding::{
      code: "QUERY_HEAVY",
      severity: "info",
      message: "most requests contain query parameters",
      value: self.query_request_percent(),
    })
  }
  result
}

///|
/// Render a Prometheus text exposition with stable metric names.
pub fn Report::to_prometheus(self : Report, prefix : String) -> String {
  let name = sanitize_metric_name(prefix)
  let mut out = "# TYPE \{name}_requests_total counter\n"
  out = out + "\{name}_requests_total \{self.requests}\n"
  out = out + "\{name}_lines_total \{self.total_lines}\n"
  out = out + "\{name}_invalid_lines_total \{self.invalid_lines}\n"
  out = out + "\{name}_filtered_lines_total \{self.filtered_lines}\n"
  out = out + "\{name}_bytes_total \{self.total_bytes}\n"
  out = out + "\{name}_error_requests_total \{self.error_requests()}\n"
  out = out + "\{name}_success_requests_total \{self.success_requests()}\n"
  out = out + "\{name}_error_rate_percent \{self.error_rate_percent()}\n"
  out = out + "\{name}_success_rate_percent \{self.success_rate_percent()}\n"
  out = out + "\{name}_invalid_rate_percent \{self.invalid_rate_percent()}\n"
  out = out + "\{name}_average_bytes \{self.average_bytes()}\n"
  out = out + "\{name}_query_request_percent \{self.query_request_percent()}\n"
  out + render_prometheus_map(name, "status", self.status_counts)
}

///|
/// Render a compact Markdown report for issue comments and release notes.
pub fn Report::to_markdown(self : Report, top? : Int = 10) -> String {
  let limit = if top < 0 { 0 } else { top }
  let mut out = "# Access log report\n\n"
  out = out + "| Metric | Value |\n| --- | ---: |\n"
  out = out + "| Requests | \{self.requests} |\n"
  out = out + "| Invalid lines | \{self.invalid_lines} |\n"
  out = out + "| Filtered lines | \{self.filtered_lines} |\n"
  out = out + "| Total bytes | \{self.total_bytes} |\n"
  out = out + "| Error rate | \{self.error_rate_percent()}% |\n"
  out = out + "| Success rate | \{self.success_rate_percent()}% |\n"
  out = out + "| Average bytes | \{self.average_bytes()} |\n\n"
  out = out + markdown_counts("## Routes", self.route_counts, limit)
  out = out +
    markdown_counts("## Status classes", self.status_class_counts(), limit)
  out = out + markdown_counts("## User agents", self.user_agent_counts, limit)
  out = out + markdown_counts("## Query keys", self.query_key_counts, limit)
  out
}

///|
/// Render one JSON object per request dimension for line-oriented pipelines.
pub fn Report::to_ndjson(self : Report) -> String {
  let mut out = ""
  for _, entry in sorted_int_entries(self.status_counts) {
    let status = entry.0
    let count = entry.1
    out = out +
      "{\"type\":\"status\",\"key\":\"" +
      status.to_string() +
      "\",\"count\":" +
      "\{count}" +
      "}\n"
  }
  for entry in sorted_string_counts(self.route_counts) {
    out = out +
      "{\"type\":\"route\",\"key\":\"" +
      json_escape(entry.0) +
      "\",\"count\":" +
      entry.1.to_string() +
      "}\n"
  }
  out
}

///|
/// Return all query parameter names in a query string.
fn query_keys(query : String) -> Array[String] {
  let result : Array[String] = []
  if query == "" || query == "-" {
    return result
  }
  for part in query.split("&") {
    let key = query_key(part.to_owned())
    if key != "" {
      result.push(key)
    }
  }
  result
}

///|
fn query_key(part : String) -> String {
  let chars = part.to_array()
  let mut index = 0
  while index < chars.length() && chars[index] != '=' {
    index += 1
  }
  String::from_array(chars[0:index]).trim().to_owned()
}

///|
fn route_depth(route : String) -> Int {
  let mut depth = 0
  for ch in route.to_array() {
    if ch == '/' {
      depth += 1
    }
  }
  if route == "/" || route == "" {
    0
  } else {
    depth
  }
}

///|
fn request_class(status : Int) -> String {
  if status >= 200 && status < 300 {
    "success"
  } else if status >= 300 && status < 400 {
    "redirect"
  } else if status >= 400 && status < 500 {
    "client_error"
  } else if status >= 500 {
    "server_error"
  } else {
    "other"
  }
}

///|
fn route_error_count(report : Report, route : String) -> Int {
  match report.route_error_counts.get(route) {
    Some(value) => value
    None => 0
  }
}

///|
fn route_bytes(report : Report, route : String) -> Int {
  match report.route_bytes_counts.get(route) {
    Some(value) => value
    None => 0
  }
}

///|
fn sanitize_metric_name(value : String) -> String {
  let out : Array[Char] = []
  for ch in value.to_array() {
    if is_metric_char(ch) {
      out.push(ch)
    } else {
      out.push('_')
    }
  }
  let result = String::from_array(out)
  if result == "" {
    "moon_accesslog"
  } else {
    result
  }
}

///|
fn is_metric_char(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '_'
}

///|
fn render_prometheus_map(
  prefix : String,
  metric : String,
  counts : Map[Int, Int],
) -> String {
  let mut out = ""
  for _, entry in sorted_int_entries(counts) {
    out = out + "\{prefix}_\{metric}_total{code=\"\{entry.0}\"} \{entry.1}\n"
  }
  out
}

///|
fn markdown_counts(
  heading : String,
  counts : Map[String, Int],
  limit : Int,
) -> String {
  let mut out = heading + "\n\n| Key | Count |\n| --- | ---: |\n"
  let mut index = 0
  for entry in sorted_string_counts(counts) {
    if index < limit {
      out = out + "| " + entry.0 + " | " + entry.1.to_string() + " |\n"
    }
    index += 1
  }
  out + "\n"
}

///|
fn sorted_int_entries(counts : Map[Int, Int]) -> Array[(Int, Int)] {
  let entries : Array[(Int, Int)] = []
  for key, value in counts {
    entries.push((key, value))
  }
  entries.sort_by(fn(a, b) {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  entries
}
