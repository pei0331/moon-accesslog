///|
/// A service-level objective snapshot derived from one report.
pub struct SloSnapshot {
  availability_percent : Int
  error_budget_percent : Int
  invalid_input_percent : Int
  query_request_percent : Int
  total_requests : Int
  server_errors : Int
}

///|
/// Return the report's core service-level indicators.
pub fn Report::slo_snapshot(self : Report) -> SloSnapshot {
  SloSnapshot::{
    availability_percent: self.success_rate_percent(),
    error_budget_percent: 100 - self.error_rate_percent(),
    invalid_input_percent: self.invalid_rate_percent(),
    query_request_percent: self.query_request_percent(),
    total_requests: self.requests,
    server_errors: self.server_error_requests(),
  }
}

///|
/// Check both an error-rate and malformed-input budget.
pub fn Report::within_budgets(
  self : Report,
  max_error_rate_percent : Int,
  max_invalid_rate_percent : Int,
) -> Bool {
  self.error_rate_percent() <= max_error_rate_percent &&
  self.invalid_rate_percent() <= max_invalid_rate_percent
}

///|
/// Return the number of distinct user agents.
pub fn Report::unique_user_agent_count(self : Report) -> Int {
  map_cardinality(self.user_agent_counts)
}

///|
/// Return the number of distinct referrers.
pub fn Report::unique_referrer_count(self : Report) -> Int {
  map_cardinality(self.referrer_counts)
}

///|
/// Return the number of distinct query parameter names.
pub fn Report::unique_query_key_count(self : Report) -> Int {
  map_cardinality(self.query_key_counts)
}

///|
/// Return the number of protocols observed.
pub fn Report::unique_protocol_count(self : Report) -> Int {
  map_cardinality(self.protocol_counts)
}

///|
/// Return the number of routes whose error rate exceeds a threshold.
pub fn Report::unhealthy_route_count(
  self : Report,
  threshold_percent : Int,
) -> Int {
  let mut total = 0
  for route, requests in self.route_counts {
    let errors = match self.route_error_counts.get(route) {
      Some(value) => value
      None => 0
    }
    if requests > 0 && errors * 100 / requests > threshold_percent {
      total += 1
    }
  }
  total
}

///|
/// Return routes ranked by error count, then route name.
pub fn Report::top_error_routes(
  self : Report,
  limit : Int,
) -> Array[(String, Int)] {
  let entries : Array[(String, Int)] = []
  for route, count in self.route_error_counts {
    entries.push((route, count))
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
  take_entries(entries, limit)
}

///|
/// Return routes ranked by transferred bytes.
pub fn Report::largest_routes(
  self : Report,
  limit : Int,
) -> Array[(String, Int)] {
  let entries : Array[(String, Int)] = []
  for route, bytes in self.route_bytes_counts {
    entries.push((route, bytes))
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
  take_entries(entries, limit)
}

///|
/// Return the percentage of requests at one route depth.
pub fn Report::route_depth_percent(self : Report, depth : Int) -> Int {
  let count = match self.route_depth_counts().get(depth) {
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
/// Render a compact environment-style key/value snapshot.
pub fn Report::to_env(self : Report, prefix : String) -> String {
  let name = sanitize_metric_name(prefix).to_upper()
  let snapshot = self.slo_snapshot()
  let mut out = "\{name}_REQUESTS=\{snapshot.total_requests}\n"
  out = out + "\{name}_ERROR_RATE_PERCENT=\{self.error_rate_percent()}\n"
  out = out + "\{name}_SUCCESS_RATE_PERCENT=\{self.success_rate_percent()}\n"
  out = out + "\{name}_INVALID_RATE_PERCENT=\{snapshot.invalid_input_percent}\n"
  out = out + "\{name}_SERVER_ERRORS=\{snapshot.server_errors}\n"
  out = out +
    "\{name}_QUERY_REQUEST_PERCENT=\{snapshot.query_request_percent}\n"
  out = out + "\{name}_UNIQUE_ROUTES=\{self.unique_path_count()}\n"
  out + "\{name}_UNHEALTHY_ROUTES=\{self.unhealthy_route_count(20)}\n"
}

///|
/// Render a deterministic JSON object containing only top-level health data.
pub fn Report::to_summary_json(self : Report) -> String {
  let snapshot = self.slo_snapshot()
  "{\"requests\":\{snapshot.total_requests},\"bytes\":\{self.total_bytes},\"error_rate_percent\":\{self.error_rate_percent()},\"success_rate_percent\":\{snapshot.availability_percent},\"invalid_rate_percent\":\{snapshot.invalid_input_percent},\"query_request_percent\":\{snapshot.query_request_percent},\"server_errors\":\{snapshot.server_errors},\"unique_routes\":\{self.unique_path_count()},\"unhealthy_routes\":\{self.unhealthy_route_count(20)}}"
}

///|
fn[K] map_cardinality(counts : Map[K, Int]) -> Int {
  let mut total = 0
  for _, _ in counts {
    total += 1
  }
  total
}

///|
fn take_entries(
  entries : Array[(String, Int)],
  limit : Int,
) -> Array[(String, Int)] {
  let result : Array[(String, Int)] = []
  let actual_limit = if limit < 0 { 0 } else { limit }
  let mut index = 0
  for entry in entries {
    if index < actual_limit {
      result.push(entry)
    }
    index += 1
  }
  result
}
