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

## Development

```bash
moon fmt --check
moon info
moon check
moon test
moon run cmd/main -- examples/access.log
moon build --target native
```

## License

Apache-2.0. See [LICENSE](LICENSE).
