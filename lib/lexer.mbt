///|
/// WIT lexer. Tokenizes a WIT 1.0 source document into a token stream with
/// line/column positions. Keywords are returned as plain identifiers and
/// resolved by the parser.

///|
pub enum TokenKind {
  /// An identifier, or a keyword (resolved by the parser).
  /// WIT escaped identifiers retain their leading `%`.
  Ident(String)
  /// A semver version string following `@`, e.g. `0.1.0`.
  Version(String)
  LBrace
  RBrace
  LParen
  RParen
  Lt
  Gt
  Comma
  Semi
  Colon
  Arrow
  Eq
  Dot
  Slash
  At
  Star
  Eof
} derive(Eq)

///|
pub struct Token {
  kind : TokenKind
  line : Int
  col : Int
} derive(Eq)

///|
pub fn Token::to_string(self : Token) -> String {
  match self.kind {
    Ident(s) => "ident(\{s})"
    Version(s) => "version(\{s})"
    LBrace => "{"
    RBrace => "}"
    LParen => "("
    RParen => ")"
    Lt => "<"
    Gt => ">"
    Comma => ","
    Semi => ";"
    Colon => ":"
    Arrow => "->"
    Eq => "="
    Dot => "."
    Slash => "/"
    At => "@"
    Star => "*"
    Eof => "eof"
  }
}

///|
/// A single-pass lexer cursor over the source.
priv struct Lexer {
  src : String
  len : Int
  mut pos : Int
  mut line : Int
  mut col : Int
}

///|
fn Lexer::make(src : String) -> Lexer {
  { src, len: src.length(), pos: 0, line: 1, col: 1 }
}

///|
/// The UTF-16 code unit `offset` positions ahead of the cursor, if in bounds.
fn Lexer::code_at(self : Lexer, offset : Int) -> UInt16? {
  let i = self.pos + offset
  if i >= 0 && i < self.len {
    Some(self.src.unsafe_get(i))
  } else {
    None
  }
}

///|
/// The character `offset` positions ahead of the cursor, if in bounds.
fn Lexer::peek_char(self : Lexer, offset : Int) -> Char? {
  match self.code_at(offset) {
    Some(c) => Some(c.to_int().unsafe_to_char())
    None => None
  }
}

///|
/// Consume one code unit, tracking line/column.
fn Lexer::advance(self : Lexer) -> Unit {
  match self.code_at(0) {
    Some(c) => {
      self.pos += 1
      if c == 0x0A {
        self.line += 1
        self.col = 1
      } else {
        self.col += 1
      }
    }
    None => ()
  }
}

///|
fn is_ident_start(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() || ch == '_'
}

///|
fn is_ident_continue(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_' || ch == '-'
}

///|
fn is_version_ident_char(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '-'
}

///|
/// Skip whitespace and `//` / `/* */` comments (doc comments `///` included).
fn Lexer::skip_trivia(self : Lexer) -> Unit raise WitError {
  for ;; {
    match self.peek_char(0) {
      Some(ch) if ch.is_whitespace() => self.advance()
      Some('/') =>
        match self.peek_char(1) {
          Some('/') =>
            for ;; {
              match self.peek_char(0) {
                Some('\n') | None => break
                _ => self.advance()
              }
            }
          Some('*') => {
            self.advance()
            self.advance()
            for ;; {
              match self.peek_char(0) {
                None =>
                  raise WitError::make(
                    self.line,
                    self.col,
                    "unterminated block comment",
                  )
                Some('*') =>
                  match self.peek_char(1) {
                    Some('/') => {
                      self.advance()
                      self.advance()
                      break
                    }
                    _ => self.advance()
                  }
                _ => self.advance()
              }
            }
          }
          _ => break
        }
      _ => break
    }
  }
}

///|
fn Lexer::lex_ident(self : Lexer) -> String {
  let start = self.pos
  for ;; {
    match self.peek_char(0) {
      Some(ch) if is_ident_continue(ch) =>
        // A '-' continues an identifier only when followed by another
        // identifier character; otherwise it starts `->`.
        if ch == '-' {
          match self.peek_char(1) {
            Some(next) if is_ident_continue(next) => self.advance()
            _ => break
          }
        } else {
          self.advance()
        }
      _ => break
    }
  }
  self.src[start:self.pos].to_owned()
}

///|
/// Lex a version string following `@`, e.g. `0.1.0` or `0.1.0-alpha`.
fn Lexer::lex_version(self : Lexer) -> String {
  let start = self.pos
  for ;; {
    match self.peek_char(0) {
      Some('.') =>
        match self.peek_char(1) {
          Some(next) if is_version_ident_char(next) => self.advance()
          _ => break
        }
      Some(ch) if is_version_ident_char(ch) || ch == '+' => self.advance()
      _ => break
    }
  }
  self.src[start:self.pos].to_owned()
}

///|
/// Skip a WIT attribute after its leading `@`, including a balanced argument
/// list. Attributes are accepted metadata but are not retained in the P0 AST.
fn Lexer::skip_attribute(self : Lexer) -> Unit raise WitError {
  ignore(self.lex_ident())
  while self.peek_char(0) is Some(ch) && ch.is_whitespace() {
    self.advance()
  }
  if self.peek_char(0) != Some('(') {
    return
  }
  let mut depth = 0
  for ;; {
    match self.peek_char(0) {
      None =>
        raise WitError::make(
          self.line,
          self.col,
          "unterminated attribute arguments",
        )
      Some('(') => {
        depth += 1
        self.advance()
      }
      Some(')') => {
        depth -= 1
        self.advance()
        if depth == 0 {
          return
        }
      }
      _ => self.advance()
    }
  }
}

///|
fn push_punct(
  tokens : Array[Token],
  kind : TokenKind,
  line : Int,
  col : Int,
) -> Unit {
  tokens.push({ kind, line, col })
}

///|
/// Tokenize a full WIT document. Raises `WitError` on an unexpected character
/// or an unterminated block comment.
pub fn tokenize(src : String) -> Array[Token] raise WitError {
  let lx = Lexer::make(src)
  let tokens : Array[Token] = Array::new()
  for ;; {
    lx.skip_trivia()
    if lx.pos >= lx.len {
      push_punct(tokens, Eof, lx.line, lx.col)
      break
    }
    let start_line = lx.line
    let start_col = lx.col
    match lx.peek_char(0) {
      Some('{') => {
        lx.advance()
        push_punct(tokens, LBrace, start_line, start_col)
      }
      Some('}') => {
        lx.advance()
        push_punct(tokens, RBrace, start_line, start_col)
      }
      Some('(') => {
        lx.advance()
        push_punct(tokens, LParen, start_line, start_col)
      }
      Some(')') => {
        lx.advance()
        push_punct(tokens, RParen, start_line, start_col)
      }
      Some('<') => {
        lx.advance()
        push_punct(tokens, Lt, start_line, start_col)
      }
      Some('>') => {
        lx.advance()
        push_punct(tokens, Gt, start_line, start_col)
      }
      Some(',') => {
        lx.advance()
        push_punct(tokens, Comma, start_line, start_col)
      }
      Some(';') => {
        lx.advance()
        push_punct(tokens, Semi, start_line, start_col)
      }
      Some(':') => {
        lx.advance()
        push_punct(tokens, Colon, start_line, start_col)
      }
      Some('.') => {
        lx.advance()
        push_punct(tokens, Dot, start_line, start_col)
      }
      Some('/') => {
        lx.advance()
        push_punct(tokens, Slash, start_line, start_col)
      }
      Some('@') => {
        lx.advance()
        match lx.peek_char(0) {
          Some(ch) if is_ident_start(ch) => lx.skip_attribute()
          _ => {
            push_punct(tokens, At, start_line, start_col)
            let v = lx.lex_version()
            push_punct(tokens, Version(v), start_line, start_col)
          }
        }
      }
      Some('*') => {
        lx.advance()
        push_punct(tokens, Star, start_line, start_col)
      }
      Some('=') => {
        lx.advance()
        push_punct(tokens, Eq, start_line, start_col)
      }
      Some('-') => {
        // `->`
        lx.advance()
        match lx.peek_char(0) {
          Some('>') => {
            lx.advance()
            push_punct(tokens, Arrow, start_line, start_col)
          }
          _ => raise WitError::make(lx.line, lx.col, "unexpected character '-'")
        }
      }
      Some('%') => {
        lx.advance()
        match lx.peek_char(0) {
          Some(ch) if is_ident_start(ch) => {
            let text = lx.lex_ident()
            tokens.push({
              kind: Ident("%" + text),
              line: start_line,
              col: start_col,
            })
          }
          _ =>
            raise WitError::make(
              start_line, start_col, "expected identifier after '%'",
            )
        }
      }
      Some(ch) if is_ident_start(ch) => {
        let text = lx.lex_ident()
        tokens.push({ kind: Ident(text), line: start_line, col: start_col })
      }
      Some(ch) =>
        raise WitError::make(
          lx.line,
          lx.col,
          "unexpected character '\{ch.to_string()}'",
        )
      None => break
    }
  }
  tokens
}
