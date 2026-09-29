# Changelog

## 0.4.0 - Unreleased

### Added

- Add User-Agent, referrer, protocol and query-key dimensions.
- Add SLO snapshots, route budgets, findings, endpoint summaries and route size
  rankings for operational dashboards.
- Add Prometheus, Markdown, NDJSON, environment and compact JSON exporters.
- Add CLI `--prometheus`, `--markdown` and `--ndjson` output modes.
- Add strict delimiter validation and whitespace-tolerant request parsing.
- Add `Report::merge`, `Report::is_healthy` and CLI `--max-error-rate` for
  parallel aggregation and CI quality gates.
- Add UTC hour-prefix filtering and reject invalid protocol, status and byte
  fields before aggregation.
- Add composable method, route-prefix, address and status-range filters through
  `AnalyzeOptions`, `analyze_with_options` and matching CLI flags.
- Add the functional incremental `Analyzer` API and `analyze_lines` helper for
  chunked or pre-split input.
- Add query-string aware `route` fields, route aggregation, status classes,
  success/client/server error metrics and structured Top-N APIs.
- Add CSV report output through `Report::to_csv()` and the CLI `--csv` flag.
- Add error request, whole-number error rate and unique-path metrics to reports.
- Add deterministic JSON report output through `Report::to_json()`.
- Add the CLI `--json` flag for archive and CI workflows.
- Add regression coverage for JSON totals and sorted path counts.

## 0.1.0

- Initial Common and Combined Log Format parser and analyzer.
