///|
/// One parsed Common or Combined Log Format record.
pub struct AccessRecord {
  address : String
  timestamp : String
  http_method : String
  path : String
  protocol : String
  status : Int
  bytes : Int
  referrer : String
  user_agent : String
}

///|
/// Aggregate report for valid and malformed log lines.
pub struct Report {
  total_lines : Int
  invalid_lines : Int
  requests : Int
  total_bytes : Int
  status_counts : Map[Int, Int]
  method_counts : Map[String, Int]
  path_counts : Map[String, Int]
  address_counts : Map[String, Int]
  hourly_counts : Map[String, Int]
}

///|
/// Parse one Common or Combined Log Format record.
pub fn parse_line(line : String) -> AccessRecord? {
  let tokens = tokenize(line)
  if tokens.length() < 7 {
    return None
  }
  let timestamp = tokens[3]
  if timestamp.length() < 2 {
    return None
  }
  let request = tokens[4]
  let parts = request.split(" ").to_array()
  if parts.length() < 3 {
    return None
  }
  let status = @string.parse_int(tokens[5]) catch { _ => return None }
  let byte_count = if tokens.length() > 6 && tokens[6] != "-" {
    @string.parse_int(tokens[6]) catch {
      _ => return None
    }
  } else {
    0
  }
  let referrer = if tokens.length() > 7 { tokens[7] } else { "-" }
  let user_agent = if tokens.length() > 8 { tokens[8] } else { "-" }
  Some(AccessRecord::{
    address: tokens[0],
    timestamp,
    http_method: parts[0].to_owned(),
    path: parts[1].to_owned(),
    protocol: parts[2].to_owned(),
    status,
    bytes: byte_count,
    referrer,
    user_agent,
  })
}

///|
/// Analyze newline-separated Common or Combined Log Format input.
pub fn analyze(source : String) -> Report {
  let status_counts : Map[Int, Int] = Map([])
  let method_counts : Map[String, Int] = Map([])
  let path_counts : Map[String, Int] = Map([])
  let address_counts : Map[String, Int] = Map([])
  let hourly_counts : Map[String, Int] = Map([])
  let mut total_lines = 0
  let mut invalid_lines = 0
  let mut requests = 0
  let mut total_bytes = 0
  for line in source.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed != "" {
      total_lines += 1
      match parse_line(trimmed) {
        Some(record) => {
          requests += 1
          total_bytes += record.bytes
          increment(status_counts, record.status)
          increment(method_counts, record.http_method)
          increment(path_counts, record.path)
          increment(address_counts, record.address)
          let hour = hour_bucket(record.timestamp)
          if hour != "" {
            increment(hourly_counts, hour)
          }
        }
        None => invalid_lines += 1
      }
    }
  }
  Report::{
    total_lines,
    invalid_lines,
    requests,
    total_bytes,
    status_counts,
    method_counts,
    path_counts,
    address_counts,
    hourly_counts,
  }
}

///|
/// Render the report as stable plain text.
pub fn Report::to_text(self : Report, top? : Int = 10) -> String {
  let limit = if top < 0 { 0 } else { top }
  let mut out = "Access log summary\n"
  out = out +
    "Lines: \{self.total_lines} (valid: \{self.requests}, invalid: \{self.invalid_lines})\n"
  out = out + "Transferred bytes: \{self.total_bytes}\n"
  out = out + "\nStatus codes\n"
  out = out + render_int_counts(self.status_counts)
  out = out + "\nMethods\n"
  out = out + render_string_counts(self.method_counts, limit)
  out = out + "\nTop paths\n"
  out = out + render_string_counts(self.path_counts, limit)
  out = out + "\nTop client addresses\n"
  out = out + render_string_counts(self.address_counts, limit)
  out = out + "\nRequests by UTC hour\n"
  out = out + render_string_counts(self.hourly_counts, 24)
  out
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
          i += 1
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
fn[K : Eq + Hash] increment(counts : Map[K, Int], key : K) -> Unit {
  let current = match counts.get(key) {
    Some(value) => value
    None => 0
  }
  counts[key] = current + 1
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
