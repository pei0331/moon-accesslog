# Changelog

## 0.2.0 - Unreleased

### Added

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
