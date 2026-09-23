# Source and License Notes

The WIT lexer, parser, AST and parse error implementation (`lib/lexer.mbt`,
`lib/parser.mbt`, `lib/ast.mbt`, `lib/error.mbt`) are a source snapshot of the project
maintained by the same author in `pei0331/moon-wit`. They are included here so
the compatibility checker builds without a registry or network connection.
The snapshot is licensed under Apache-2.0, like this module. When the WIT
grammar changes, sync these files from the upstream project and run `moon test`.

The compatibility comparison and its tests are original to this module.
