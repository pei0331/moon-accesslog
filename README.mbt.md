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

## Development

```bash
moon fmt --check
moon info
moon check
moon test
moon run cmd/main -- examples/access.log
moon run cmd/main -- --json examples/access.log
moon build --target native
```

## License

Apache-2.0. See [LICENSE](LICENSE).
