///|
/// Optional predicates applied while analyzing access log records.
pub struct AnalyzeOptions {
  http_method : String?
  path_prefix : String?
  address : String?
  status_min : Int?
  status_max : Int?
  hour_prefix : String?
}

///|
/// Create an analyzer with no filters.
pub fn AnalyzeOptions::new() -> AnalyzeOptions {
  AnalyzeOptions::{
    http_method: None,
    path_prefix: None,
    address: None,
    status_min: None,
    status_max: None,
    hour_prefix: None,
  }
}

///|
/// Build filters for a method, route prefix, address and inclusive status range.
pub fn AnalyzeOptions::from(
  http_method : String?,
  path_prefix : String?,
  address : String?,
  status_min : Int?,
  status_max : Int?,
) -> AnalyzeOptions {
  AnalyzeOptions::{
    http_method,
    path_prefix,
    address,
    status_min,
    status_max,
    hour_prefix: None,
  }
}

///|
/// Restrict analysis to records whose timestamp starts with a UTC hour prefix.
pub fn AnalyzeOptions::with_hour_prefix(
  self : AnalyzeOptions,
  hour_prefix : String?,
) -> AnalyzeOptions {
  AnalyzeOptions::{
    http_method: self.http_method,
    path_prefix: self.path_prefix,
    address: self.address,
    status_min: self.status_min,
    status_max: self.status_max,
    hour_prefix,
  }
}

///|
/// Analyze input while applying optional method, route, address and status filters.
pub fn analyze_with_options(
  source : String,
  options : AnalyzeOptions,
) -> Report {
  let mut analyzer = Analyzer::new(options)
  for line in source.split("\n") {
    analyzer = analyzer.push(line.to_owned())
  }
  analyzer.finish()
}

///|
/// A functional incremental analyzer suitable for chunked readers.
pub struct Analyzer {
  options : AnalyzeOptions
  mut report : Report
}

///|
/// Create an incremental analyzer.
pub fn Analyzer::new(options : AnalyzeOptions) -> Analyzer {
  Analyzer::{ options, report: empty_report() }
}

///|
/// Consume one line and return the updated analyzer.
pub fn Analyzer::push(self : Analyzer, line : String) -> Analyzer {
  let state = self
  let trimmed = line.trim().to_owned()
  if trimmed == "" {
    return state
  }
  state.report.total_lines += 1
  match parse_line(trimmed) {
    None => state.report.invalid_lines += 1
    Some(record) =>
      if matches_options(state.options, record) {
        state.report = add_record(state.report, record)
      } else {
        state.report.filtered_lines += 1
      }
  }
  state
}

///|
/// Finish an incremental analysis and return its report.
pub fn Analyzer::finish(self : Analyzer) -> Report {
  self.report
}

///|
/// Analyze an array of already split lines.
pub fn analyze_lines(lines : Array[String], options : AnalyzeOptions) -> Report {
  let mut analyzer = Analyzer::new(options)
  for line in lines {
    analyzer = analyzer.push(line)
  }
  analyzer.finish()
}

///|
fn empty_report() -> Report {
  Report::{
    total_lines: 0,
    invalid_lines: 0,
    filtered_lines: 0,
    requests: 0,
    total_bytes: 0,
    query_requests: 0,
    status_counts: Map([]),
    method_counts: Map([]),
    path_counts: Map([]),
    address_counts: Map([]),
    hourly_counts: Map([]),
    route_counts: Map([]),
    user_agent_counts: Map([]),
    referrer_counts: Map([]),
    query_key_counts: Map([]),
    protocol_counts: Map([]),
    route_error_counts: Map([]),
    route_bytes_counts: Map([]),
  }
}

///|
fn matches_options(options : AnalyzeOptions, record : AccessRecord) -> Bool {
  let method_matches = match options.http_method {
    Some(value) => record.http_method == value
    None => true
  }
  let path_matches = match options.path_prefix {
    Some(value) => record.route.has_prefix(value)
    None => true
  }
  let address_matches = match options.address {
    Some(value) => record.address == value
    None => true
  }
  let min_matches = match options.status_min {
    Some(value) => record.status >= value
    None => true
  }
  let max_matches = match options.status_max {
    Some(value) => record.status <= value
    None => true
  }
  let hour_matches = match options.hour_prefix {
    Some(value) => record.timestamp.has_prefix(value)
    None => true
  }
  method_matches &&
  path_matches &&
  address_matches &&
  min_matches &&
  max_matches &&
  hour_matches
}

///|
fn add_record(report : Report, record : AccessRecord) -> Report {
  report.requests += 1
  report.total_bytes += record.bytes
  if record.query != "" {
    report.query_requests += 1
  }
  increment(report.status_counts, record.status)
  increment(report.method_counts, record.http_method)
  increment(report.path_counts, record.path)
  increment(report.route_counts, record.route)
  increment_by(report.route_bytes_counts, record.route, record.bytes)
  if record.status >= 400 {
    increment(report.route_error_counts, record.route)
  }
  increment(report.address_counts, record.address)
  increment(report.user_agent_counts, record.user_agent)
  increment(report.referrer_counts, record.referrer)
  increment(report.protocol_counts, record.protocol)
  for key in query_keys(record.query) {
    increment(report.query_key_counts, key)
  }
  let hour = hour_bucket(record.timestamp)
  if hour != "" {
    increment(report.hourly_counts, hour)
  }
  report
}

///|
/// Number of successful (2xx and 3xx) requests.
pub fn Report::success_requests(self : Report) -> Int {
  let mut total = 0
  for status, count in self.status_counts {
    if status >= 200 && status < 400 {
      total += count
    }
  }
  total
}

///|
/// Number of client failures (4xx).
pub fn Report::client_error_requests(self : Report) -> Int {
  let mut total = 0
  for status, count in self.status_counts {
    if status >= 400 && status < 500 {
      total += count
    }
  }
  total
}

///|
/// Number of server failures (5xx and above).
pub fn Report::server_error_requests(self : Report) -> Int {
  let mut total = 0
  for status, count in self.status_counts {
    if status >= 500 {
      total += count
    }
  }
  total
}

///|
/// Successful request percentage rounded down to a whole number.
pub fn Report::success_rate_percent(self : Report) -> Int {
  if self.requests == 0 {
    0
  } else {
    self.success_requests() * 100 / self.requests
  }
}

///|
/// Return whether the report is within an inclusive error-rate budget.
pub fn Report::is_healthy(self : Report, max_error_rate_percent : Int) -> Bool {
  self.error_rate_percent() <= max_error_rate_percent
}

///|
/// Combine two reports produced with the same analysis options.
pub fn Report::merge(self : Report, other : Report) -> Report {
  self.total_lines += other.total_lines
  self.invalid_lines += other.invalid_lines
  self.filtered_lines += other.filtered_lines
  self.requests += other.requests
  self.total_bytes += other.total_bytes
  self.query_requests += other.query_requests
  merge_int_counts(self.status_counts, other.status_counts)
  merge_string_counts(self.method_counts, other.method_counts)
  merge_string_counts(self.path_counts, other.path_counts)
  merge_string_counts(self.route_counts, other.route_counts)
  merge_string_counts(self.address_counts, other.address_counts)
  merge_string_counts(self.hourly_counts, other.hourly_counts)
  merge_string_counts(self.user_agent_counts, other.user_agent_counts)
  merge_string_counts(self.referrer_counts, other.referrer_counts)
  merge_string_counts(self.query_key_counts, other.query_key_counts)
  merge_string_counts(self.protocol_counts, other.protocol_counts)
  merge_string_counts(self.route_error_counts, other.route_error_counts)
  merge_string_counts(self.route_bytes_counts, other.route_bytes_counts)
  self
}

///|
fn merge_int_counts(target : Map[Int, Int], source : Map[Int, Int]) -> Unit {
  for key, value in source {
    let current = match target.get(key) {
      Some(existing) => existing
      None => 0
    }
    target[key] = current + value
  }
}

///|
fn merge_string_counts(
  target : Map[String, Int],
  source : Map[String, Int],
) -> Unit {
  for key, value in source {
    let current = match target.get(key) {
      Some(existing) => existing
      None => 0
    }
    target[key] = current + value
  }
}

///|
/// Return counts grouped into HTTP status classes such as `2xx` and `5xx`.
pub fn Report::status_class_counts(self : Report) -> Map[String, Int] {
  let result : Map[String, Int] = Map([])
  for status, count in self.status_counts {
    let class = status_class(status)
    let current = match result.get(class) {
      Some(value) => value
      None => 0
    }
    result[class] = current + count
  }
  result
}

///|
fn status_class(status : Int) -> String {
  if status >= 100 && status < 200 {
    "1xx"
  } else if status >= 200 && status < 300 {
    "2xx"
  } else if status >= 300 && status < 400 {
    "3xx"
  } else if status >= 400 && status < 500 {
    "4xx"
  } else if status >= 500 && status < 600 {
    "5xx"
  } else {
    "other"
  }
}

///|
/// Return the most frequent paths, sorted by count then path.
pub fn Report::top_paths(self : Report, limit : Int) -> Array[(String, Int)] {
  take_string_counts(self.path_counts, limit)
}

///|
/// Return the most frequent routes with query strings removed.
pub fn Report::top_routes(self : Report, limit : Int) -> Array[(String, Int)] {
  take_string_counts(self.route_counts, limit)
}

///|
/// Return the most frequent client addresses.
pub fn Report::top_addresses(
  self : Report,
  limit : Int,
) -> Array[(String, Int)] {
  take_string_counts(self.address_counts, limit)
}

///|
fn take_string_counts(
  counts : Map[String, Int],
  limit : Int,
) -> Array[(String, Int)] {
  let entries = sorted_string_counts(counts)
  let actual_limit = if limit < 0 { 0 } else { limit }
  let result : Array[(String, Int)] = []
  let mut index = 0
  for entry in entries {
    if index < actual_limit {
      result.push(entry)
    }
    index += 1
  }
  result
}

///|
fn sorted_string_counts(counts : Map[String, Int]) -> Array[(String, Int)] {
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
  entries
}
