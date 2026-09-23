///|
/// A lexer/parser error with 1-based line and column position.
pub(all) suberror WitError {
  At(Int, Int, String)
}

///|
pub fn WitError::make(line : Int, col : Int, message : String) -> WitError {
  At(line, col, message)
}

///|
/// Formats as `line:col: message`.
pub fn WitError::to_string(self : WitError) -> String {
  match self {
    At(line, col, message) => "\{line}:\{col}: \{message}"
  }
}
