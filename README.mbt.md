# moon-accesslog

`moon-accesslog` is a dependency-free MoonBit analyzer for Nginx and Apache
Common/Combined access logs. It parses quoted request fields correctly and
turns a large log into a compact operational summary: requests, transferred
bytes, status and method counts, top paths, client addresses, and UTC-hour
traffic.

## Quick start

```bash
moon run cmd/main -- examples/access.log
moon run cmd/main -- --top 5 examples/access.log
moon run cmd/main -- --json examples/access.log
moon run cmd/main -- --csv examples/access.log
moon run cmd/main -- --method GET --path-prefix /api examples/access.log
moon run cmd/main -- --status-min 400 --status-max 599 --json examples/access.log
moon run cmd/main -- --max-error-rate 5 examples/access.log
```

Malformed records are counted and skipped, while valid lines still contribute
to the report. The first release loads the selected file into memory before
analysis; it is intended for operational log files, not unbounded streams.

## Library API

```moonbit nocheck
let report = @accesslog.analyze(source)
println(report.to_text(top=10))
```

`parse_line` accepts Common and Combined Log Format entries and returns a
structured record. `analyze` aggregates records without making network calls
or depending on a server runtime.

`Report::to_json()` emits deterministic JSON with totals and sorted count maps
for status codes, methods, paths, client addresses and UTC-hour buckets. The
CLI's `--json` flag selects the same machine-readable format for archival and
CI pipelines; `--top` remains available for the human-readable report.

`Report::to_csv()` and the CLI's `--csv` option emit a header plus normalized
`metric,key,value` rows. Values are escaped according to CSV rules, and the
same stable ordering is used on every run.

Reports also expose `error_requests()`, `error_rate_percent()` and
`unique_path_count()` for health checks and dashboards. Error requests include
both client and server failures (HTTP status 400 and above); the percentage is
rounded down to a whole number.
`Report::is_healthy(max_error_rate_percent)` provides the same inclusive budget
check for library callers. The CLI's `--max-error-rate N` exits with an error
when the analyzed report exceeds that budget, making it suitable for CI gates.

Filtering is available without changing the source data. The CLI accepts
`--method`, `--path-prefix`, `--address`, `--status-min` and `--status-max`;
filtered valid records are reported separately as `filtered_lines`. The library
equivalent is `AnalyzeOptions::from(...)` plus `analyze_with_options(...)`.

Every record exposes both its original request target (`path`) and the route
with the query string removed (`route`). Reports include route counts, HTTP
status-class counts, success/client-error/server-error metrics, and structured
`top_paths`, `top_routes` and `top_addresses` results. `Analyzer::push` and
`analyze_lines` support incremental or pre-split input for callers that do not
want to assemble one large source string.

## Development

```bash
moon fmt --check
moon info
moon check
moon test
moon run cmd/main -- examples/access.log
moon run cmd/main -- --json examples/access.log
moon run cmd/main -- --status-min 400 examples/access.log
moon build --target native
```

The test suite covers malformed records, quoted fields, query/route handling,
filter accounting, deterministic output ordering, incremental analysis and
status health metrics.

## License

Apache-2.0. See [LICENSE](LICENSE).
