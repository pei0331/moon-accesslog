# moon-wit-compat

`moon-wit-compat` compares two WIT package versions and reports public API
changes before a component interface is released. It focuses on compatibility
analysis, not binding generation.

## Quick start

```bash
moon run cmd/main -- examples/v1.wit examples/v2-breaking.wit
moon run cmd/main -- --strict examples/v1.wit examples/v2-breaking.wit
```

`--strict` exits unsuccessfully when a breaking change is found, making the
tool suitable for release checks in CI.

## Compatibility policy

- Removing a declaration is breaking.
- Changing an existing function signature, type definition, import, export,
  `use`, or world composition entry is breaking.
- Adding a declaration is reported as additive and does not fail strict mode.
- Package namespace or name changes are breaking.

Imports and exports are treated conservatively and uniformly because a WIT
document alone does not say which side of an interface is the release target.
The comparison is structural over the parsed WIT subset supported by
`moon-wit`; it does not resolve transitive `include` or `use` dependencies.

## Library API

```moonbit nocheck
let old_package = @wit.parse(old_source)
let new_package = @wit.parse(new_source)
let report = @compat.compare(old_package, new_package)
println(report.to_string())
if report.has_breaking() {
  abort("release is not compatible")
}
```

## Development

```bash
moon info
moon fmt
moon test
moon run cmd/main -- examples/v1.wit examples/v2-breaking.wit
```

## License

Apache-2.0. See [LICENSE](LICENSE).
