///|
/// Recursive-descent parser for the WIT 1.0 core subset.
///
/// Parses: `package`, `interface`, `world`, `use`, `import`/`export`,
/// `record`/`variant`/`enum`/`flags`/`resource`/`type` aliases and `func`
/// signatures, including named results and inline interfaces in worlds.
/// Raises `WitError` with 1-based line/column positions on malformed input.
/// Design inspired by bytecodealliance/wit-bindgen.

///|
priv struct Parser {
  tokens : Array[Token]
  mut idx : Int
}

///|
fn Parser::make(tokens : Array[Token]) -> Parser {
  { tokens, idx: 0 }
}

///|
fn Parser::peek(self : Parser, offset : Int) -> Token {
  let i = self.idx + offset
  if i >= self.tokens.length() {
    self.tokens[self.tokens.length() - 1]
  } else {
    self.tokens[i]
  }
}

///|
fn Parser::advance(self : Parser) -> Unit {
  if self.peek(0).kind != Eof {
    self.idx += 1
  }
}

///|
fn Parser::check_kw(self : Parser, kw : String) -> Bool {
  match self.peek(0).kind {
    Ident(text) => text == kw
    _ => false
  }
}

///|
fn Parser::error_here(self : Parser, message : String) -> WitError {
  let tok = self.peek(0)
  WitError::make(tok.line, tok.col, message)
}

///|
fn Parser::expect_ident(self : Parser) -> String raise WitError {
  match self.peek(0).kind {
    Ident(text) => {
      self.advance()
      text
    }
    _ =>
      raise self.error_here(
        "expected identifier, found \{self.peek(0).to_string()}",
      )
  }
}

///|
fn Parser::expect_kw(self : Parser, kw : String) -> Unit raise WitError {
  match self.peek(0).kind {
    Ident(text) if text == kw => self.advance()
    _ =>
      raise self.error_here(
        "expected keyword '\{kw}', found \{self.peek(0).to_string()}",
      )
  }
}

///|
fn Parser::expect_punct(
  self : Parser,
  kind : TokenKind,
  what : String,
) -> Unit raise WitError {
  if self.peek(0).kind == kind {
    self.advance()
  } else {
    raise self.error_here("expected \{what}, found \{self.peek(0).to_string()}")
  }
}

///|
/// Parse a WIT document into a [`WitPackage`].
pub fn parse(src : String) -> WitPackage raise WitError {
  let tokens = tokenize(src)
  let p = Parser::make(tokens)
  p.parse_package()
}

///|
fn Parser::parse_package(self : Parser) -> WitPackage raise WitError {
  let mut ns = "root"
  let mut pkg_name = "package"
  let mut version : String? = None
  if self.check_kw("package") {
    self.advance()
    ns = self.expect_ident()
    self.expect_punct(Colon, "':'")
    pkg_name = self.expect_ident()
    if self.peek(0).kind == At {
      self.advance()
      match self.peek(0).kind {
        Version(v) => {
          version = Some(v)
          self.advance()
        }
        _ => raise self.error_here("expected a version after '@'")
      }
    }
    self.expect_punct(Semi, "';'")
  }
  let items : Array[WitItem] = Array::new()
  while self.peek(0).kind != Eof {
    match self.peek(0).kind {
      Ident(text) if text == "interface" =>
        items.push(Interface(self.parse_interface()))
      Ident(text) if text == "world" => items.push(World(self.parse_world()))
      Ident(text) if text == "use" => items.push(Use(self.parse_use()))
      _ =>
        raise self.error_here(
          "expected 'interface', 'world' or 'use', found \{self.peek(0).to_string()}",
        )
    }
  }
  { ns, name: pkg_name, version, items }
}

///|
fn Parser::parse_interface(self : Parser) -> Interface raise WitError {
  self.expect_kw("interface")
  let name = self.expect_ident()
  match self.peek(0).kind {
    Semi => {
      self.advance()
      { name, items: Array::new() }
    }
    LBrace => {
      self.advance()
      let items = self.parse_interface_items()
      self.expect_punct(RBrace, "'}'")
      { name, items }
    }
    _ =>
      raise self.error_here(
        "expected '{{' or ';' after interface name, found \{self.peek(0).to_string()}",
      )
  }
}

///|
fn Parser::parse_interface_items(
  self : Parser,
) -> Array[InterfaceItem] raise WitError {
  let items : Array[InterfaceItem] = Array::new()
  while self.peek(0).kind != RBrace && self.peek(0).kind != Eof {
    items.push(self.parse_interface_item())
  }
  items
}

///|
fn Parser::parse_interface_item(self : Parser) -> InterfaceItem raise WitError {
  match self.peek(0).kind {
    Ident(text) if text == "use" => Use(self.parse_use())
    Ident(text) if text == "type" => Type(self.parse_type_alias())
    Ident(text) if text == "record" => Type(self.parse_record())
    Ident(text) if text == "variant" => Type(self.parse_variant())
    Ident(text) if text == "enum" => Type(self.parse_enum())
    Ident(text) if text == "flags" => Type(self.parse_flags())
    Ident(text) if text == "resource" => Type(self.parse_resource())
    Ident(_) => Func(self.parse_func())
    _ =>
      raise self.error_here(
        "expected an interface item, found \{self.peek(0).to_string()}",
      )
  }
}

///|
fn Parser::parse_world(self : Parser) -> World raise WitError {
  self.expect_kw("world")
  let name = self.expect_ident()
  match self.peek(0).kind {
    Semi => {
      self.advance()
      { name, items: Array::new() }
    }
    LBrace => {
      self.advance()
      let items : Array[WorldItem] = Array::new()
      while self.peek(0).kind != RBrace && self.peek(0).kind != Eof {
        match self.peek(0).kind {
          Ident(text) if text == "use" => items.push(Use(self.parse_use()))
          Ident(text) if text == "include" => {
            let (path, names) = self.parse_include()
            items.push(Include(path, names))
          }
          Ident(text) if text == "import" =>
            if self.check_world_func("import") {
              items.push(ImportFunc(self.parse_world_func("import")))
            } else {
              items.push(Import(self.parse_impexp("import")))
            }
          Ident(text) if text == "export" =>
            if self.check_world_func("export") {
              items.push(ExportFunc(self.parse_world_func("export")))
            } else {
              items.push(Export(self.parse_impexp("export")))
            }
          _ =>
            raise self.error_here(
              "expected 'include', 'import', 'export' or 'use', found \{self.peek(0).to_string()}",
            )
        }
      }
      self.expect_punct(RBrace, "'}'")
      { name, items }
    }
    _ =>
      raise self.error_here(
        "expected '{{' or ';' after world name, found \{self.peek(0).to_string()}",
      )
  }
}

///|
fn Parser::parse_include(
  self : Parser,
) -> (String, Array[UseName]) raise WitError {
  self.expect_kw("include")
  let mut path = ""
  let mut saw_segment = false
  for ;; {
    match self.peek(0).kind {
      Ident("with") if saw_segment => break
      Ident(text) => {
        path = path + text
        saw_segment = true
        self.advance()
      }
      Colon => {
        path = path + ":"
        self.advance()
      }
      Slash => {
        path = path + "/"
        self.advance()
      }
      At => {
        path = path + "@"
        self.advance()
        match self.peek(0).kind {
          Version(v) => {
            path = path + v
            self.advance()
          }
          _ => raise self.error_here("expected a version after '@'")
        }
      }
      Dot =>
        match self.peek(1).kind {
          Ident("with") => break
          _ => {
            path = path + "."
            self.advance()
          }
        }
      _ => break
    }
  }
  if !saw_segment {
    raise self.error_here("expected a world path after 'include'")
  }
  let names : Array[UseName] = Array::new()
  if self.check_kw("with") {
    self.advance()
    self.expect_punct(LBrace, "'{' after 'with'")
    while self.peek(0).kind != RBrace {
      let source = self.expect_ident()
      self.expect_kw("as")
      let target = self.expect_ident()
      names.push({ name: source, asName: Some(target) })
      if self.peek(0).kind == Comma {
        self.advance()
      } else {
        break
      }
    }
    self.expect_punct(RBrace, "'}'")
  }
  self.expect_punct(Semi, "';'")
  (path, names)
}

///|
fn Parser::check_world_func(self : Parser, kw : String) -> Bool {
  if !self.check_kw(kw) {
    return false
  }
  match (self.peek(1).kind, self.peek(2).kind, self.peek(3).kind) {
    (Ident(_), Colon, Ident("func")) => true
    _ => false
  }
}

///|
fn Parser::parse_world_func(
  self : Parser,
  kw : String,
) -> FuncSig raise WitError {
  self.expect_kw(kw)
  let name = self.expect_ident()
  self.expect_punct(Colon, "':'")
  self.parse_func_after_name(name)
}

///|
fn Parser::parse_impexp(self : Parser, kw : String) -> ImpExp raise WitError {
  self.expect_kw(kw)
  let name = self.parse_impexp_path()
  let as_name = if self.check_kw("as") {
    self.advance()
    Some(self.expect_ident())
  } else {
    None
  }
  let inline = if self.peek(0).kind == Colon {
    self.advance()
    self.expect_kw("interface")
    match self.peek(0).kind {
      Semi => {
        self.advance()
        Some(({ name: "", items: Array::new() } : Interface))
      }
      LBrace => {
        self.advance()
        let items = self.parse_interface_items()
        self.expect_punct(RBrace, "'}'")
        Some(({ name: "", items } : Interface))
      }
      _ =>
        raise self.error_here(
          "expected ';' or '{{' after 'interface', found \{self.peek(0).to_string()}",
        )
    }
  } else {
    None
  }
  if inline is None {
    self.expect_punct(Semi, "';'")
  }
  { name, asName: as_name, inline }
}

///|
fn Parser::parse_impexp_path(self : Parser) -> String raise WitError {
  let mut path = self.expect_ident()
  for ;; {
    match self.peek(0).kind {
      Colon =>
        match self.peek(1).kind {
          Ident("interface") => break
          _ => {
            path = path + ":"
            self.advance()
          }
        }
      Slash => {
        path = path + "/"
        self.advance()
      }
      Dot => {
        path = path + "."
        self.advance()
      }
      At => {
        path = path + "@"
        self.advance()
        match self.peek(0).kind {
          Version(v) => {
            path = path + v
            self.advance()
          }
          _ => raise self.error_here("expected a version after '@'")
        }
      }
      Ident(text) if text != "as" => {
        path = path + text
        self.advance()
      }
      _ => break
    }
  }
  path
}

///|
fn Parser::parse_use(self : Parser) -> UseDecl raise WitError {
  self.expect_kw("use")
  let path = self.parse_use_path()
  self.expect_punct(Dot, "'.'")
  let names : Array[UseName] = Array::new()
  match self.peek(0).kind {
    Star =>
      // `use foo.*` — re-export everything; kept as an empty name list.
      self.advance()
    LBrace => {
      self.advance()
      while self.peek(0).kind != RBrace {
        let n = self.expect_ident()
        let as_name = if self.check_kw("as") {
          self.advance()
          Some(self.expect_ident())
        } else {
          None
        }
        names.push({ name: n, asName: as_name })
        if self.peek(0).kind == Comma {
          self.advance()
        } else {
          break
        }
      }
      self.expect_punct(RBrace, "'}'")
    }
    _ =>
      raise self.error_here(
        "expected '.{{' or '.*' after use path, found \{self.peek(0).to_string()}",
      )
  }
  self.expect_punct(Semi, "';'")
  { path, names }
}

///|
/// Collect a `use` path such as `wasi:io/streams` from identifier / `:` / `/` /
/// `.` tokens, stopping before the final `.` that precedes `{` or `*`.
fn Parser::parse_use_path(self : Parser) -> String {
  let mut s = ""
  for ;; {
    match self.peek(0).kind {
      Ident(text) => {
        s = s + text
        self.advance()
      }
      Colon => {
        s = s + ":"
        self.advance()
      }
      Slash => {
        s = s + "/"
        self.advance()
      }
      At => {
        s = s + "@"
        self.advance()
        match self.peek(0).kind {
          Version(v) => {
            s = s + v
            self.advance()
          }
          _ => return s
        }
      }
      Dot =>
        match self.peek(1).kind {
          LBrace | Star => break
          _ => {
            s = s + "."
            self.advance()
          }
        }
      _ => break
    }
  }
  s
}

///|
fn Parser::parse_type_alias(self : Parser) -> TypeDef raise WitError {
  self.expect_kw("type")
  let name = self.expect_ident()
  self.expect_punct(Eq, "'='")
  let ty = self.parse_type()
  self.expect_punct(Semi, "';'")
  { name, kind: Alias(ty) }
}

///|
fn Parser::parse_record(self : Parser) -> TypeDef raise WitError {
  self.expect_kw("record")
  let name = self.expect_ident()
  self.expect_punct(LBrace, "'{'")
  let fields : Array[Field] = Array::new()
  while self.peek(0).kind != RBrace {
    let fname = self.expect_ident()
    self.expect_punct(Colon, "':'")
    let ty = self.parse_type()
    fields.push({ name: fname, ty })
    if self.peek(0).kind == Comma {
      self.advance()
    }
  }
  self.expect_punct(RBrace, "'}'")
  { name, kind: Record(fields) }
}

///|
fn Parser::parse_variant(self : Parser) -> TypeDef raise WitError {
  self.expect_kw("variant")
  let name = self.expect_ident()
  self.expect_punct(LBrace, "'{'")
  let cases : Array[Case] = Array::new()
  while self.peek(0).kind != RBrace {
    let cname = self.expect_ident()
    let ty = if self.peek(0).kind == LParen {
      self.advance()
      let t = self.parse_type()
      self.expect_punct(RParen, "')'")
      Some(t)
    } else {
      None
    }
    cases.push({ name: cname, ty })
    if self.peek(0).kind == Comma {
      self.advance()
    }
  }
  self.expect_punct(RBrace, "'}'")
  { name, kind: Variant(cases) }
}

///|
fn Parser::parse_name_list(self : Parser) -> Array[String] raise WitError {
  let names : Array[String] = Array::new()
  while self.peek(0).kind != RBrace {
    names.push(self.expect_ident())
    if self.peek(0).kind == Comma {
      self.advance()
    }
  }
  names
}

///|
fn Parser::parse_enum(self : Parser) -> TypeDef raise WitError {
  self.expect_kw("enum")
  let name = self.expect_ident()
  self.expect_punct(LBrace, "'{'")
  let names = self.parse_name_list()
  self.expect_punct(RBrace, "'}'")
  { name, kind: Enum(names) }
}

///|
fn Parser::parse_flags(self : Parser) -> TypeDef raise WitError {
  self.expect_kw("flags")
  let name = self.expect_ident()
  self.expect_punct(LBrace, "'{'")
  let names = self.parse_name_list()
  self.expect_punct(RBrace, "'}'")
  { name, kind: Flags(names) }
}

///|
fn Parser::parse_resource(self : Parser) -> TypeDef raise WitError {
  self.expect_kw("resource")
  let name = self.expect_ident()
  if self.peek(0).kind == Semi {
    self.advance()
    return { name, kind: Resource(Array::new()) }
  }
  self.expect_punct(LBrace, "'{'")
  let funcs : Array[ResourceFunc] = Array::new()
  while self.peek(0).kind != RBrace {
    let kind = if self.check_kw("constructor") {
      self.advance()
      Constructor
    } else if self.check_kw("static") {
      self.advance()
      Static
    } else {
      Method
    }
    let sig = if kind is Constructor {
      self.parse_func_signature("new")
    } else {
      self.parse_func()
    }
    funcs.push({ kind, sig })
  }
  self.expect_punct(RBrace, "'}'")
  { name, kind: Resource(funcs) }
}

///|
fn Parser::parse_func(self : Parser) -> FuncSig raise WitError {
  let name = self.expect_ident()
  self.expect_punct(Colon, "':'")
  self.parse_func_after_name(name)
}

///|
fn Parser::parse_func_after_name(
  self : Parser,
  name : String,
) -> FuncSig raise WitError {
  self.expect_kw("func")
  self.parse_func_signature(name)
}

///|
fn Parser::parse_func_signature(
  self : Parser,
  name : String,
) -> FuncSig raise WitError {
  self.expect_punct(LParen, "'('")
  let params : Array[Field] = Array::new()
  while self.peek(0).kind != RParen {
    let pname = self.expect_ident()
    self.expect_punct(Colon, "':'")
    let ty = self.parse_type()
    params.push({ name: pname, ty })
    if self.peek(0).kind == Comma {
      self.advance()
    } else {
      break
    }
  }
  self.expect_punct(RParen, "')'")
  let results = if self.peek(0).kind == Arrow {
    self.advance()
    self.parse_results()
  } else {
    Array::new()
  }
  if self.peek(0).kind == Semi {
    self.advance()
  }
  { name, params, results }
}

///|
fn Parser::parse_results(self : Parser) -> Array[FuncResult] raise WitError {
  if self.peek(0).kind == LParen {
    // `-> (t1, t2)` or `-> (a: t1, b: t2)` or `-> ()`
    self.advance()
    let results : Array[FuncResult] = Array::new()
    if self.peek(0).kind != RParen {
      for ;; {
        if self.peek(1).kind == Colon {
          let n = self.expect_ident()
          self.expect_punct(Colon, "':'")
          let t = self.parse_type()
          results.push(Named({ name: n, ty: t }))
        } else {
          let t = self.parse_type()
          results.push(Unnamed(t))
        }
        if self.peek(0).kind == Comma {
          self.advance()
        } else {
          break
        }
      }
    }
    self.expect_punct(RParen, "')'")
    results
  } else {
    // single unnamed result: `-> t`
    let t = self.parse_type()
    [Unnamed(t)]
  }
}

///|
fn Parser::parse_type(self : Parser) -> WitType raise WitError {
  match self.peek(0).kind {
    Ident(text) =>
      match text {
        "u8" => {
          self.advance()
          U8
        }
        "u16" => {
          self.advance()
          U16
        }
        "u32" => {
          self.advance()
          U32
        }
        "u64" => {
          self.advance()
          U64
        }
        "s8" => {
          self.advance()
          S8
        }
        "s16" => {
          self.advance()
          S16
        }
        "s32" => {
          self.advance()
          S32
        }
        "s64" => {
          self.advance()
          S64
        }
        "f32" => {
          self.advance()
          F32
        }
        "f64" => {
          self.advance()
          F64
        }
        "char" => {
          self.advance()
          TChar
        }
        "string" => {
          self.advance()
          TString
        }
        "bool" => {
          self.advance()
          TBool
        }
        "list" => {
          self.advance()
          List(self.parse_angle_arg())
        }
        "option" => {
          self.advance()
          Option(self.parse_angle_arg())
        }
        "result" => {
          self.advance()
          self.parse_result_type()
        }
        "tuple" => {
          self.advance()
          self.parse_tuple_type()
        }
        "own" => {
          self.advance()
          Own(self.parse_resource_ref("own"))
        }
        "borrow" => {
          self.advance()
          Borrow(self.parse_resource_ref("borrow"))
        }
        "future" => {
          self.advance()
          Future(self.parse_optional_angle_arg())
        }
        "stream" => {
          self.advance()
          Stream(self.parse_optional_angle_arg())
        }
        _ => {
          self.advance()
          Name(text)
        }
      }
    _ =>
      raise self.error_here(
        "expected a type, found \{self.peek(0).to_string()}",
      )
  }
}

///|
fn Parser::parse_optional_angle_arg(self : Parser) -> WitType? raise WitError {
  self.expect_punct(Lt, "'<'")
  let value = match self.peek(0).kind {
    Ident("_") => {
      self.advance()
      None
    }
    _ => Some(self.parse_type())
  }
  self.expect_punct(Gt, "'>'")
  value
}

///|
fn Parser::parse_angle_arg(self : Parser) -> WitType raise WitError {
  self.expect_punct(Lt, "'<'")
  let t = self.parse_type()
  self.expect_punct(Gt, "'>'")
  t
}

///|
fn Parser::parse_result_type(self : Parser) -> WitType raise WitError {
  self.expect_punct(Lt, "'<'")
  let ok = self.parse_result_slot()
  let err = if self.peek(0).kind == Comma {
    self.advance()
    self.parse_result_slot()
  } else {
    None
  }
  self.expect_punct(Gt, "'>'")
  Result(ok, err)
}

///|
fn Parser::parse_result_slot(self : Parser) -> WitType? raise WitError {
  match self.peek(0).kind {
    Ident("_") => {
      self.advance()
      None
    }
    Ident("nil") => {
      self.advance()
      None
    }
    _ => Some(self.parse_type())
  }
}

///|
fn Parser::parse_tuple_type(self : Parser) -> WitType raise WitError {
  self.expect_punct(Lt, "'<'")
  let items : Array[WitType] = Array::new()
  items.push(self.parse_type())
  while self.peek(0).kind == Comma {
    self.advance()
    items.push(self.parse_type())
  }
  self.expect_punct(Gt, "'>'")
  Tuple(items)
}

///|
/// The resource type name inside `own<...>` / `borrow<...>`.
fn Parser::parse_resource_ref(
  self : Parser,
  what : String,
) -> String raise WitError {
  self.expect_punct(Lt, "'<'")
  let t = self.parse_type()
  self.expect_punct(Gt, "'>'")
  match t {
    Name(n) => n
    _ => raise self.error_here("expected a type name inside '\{what}<>'")
  }
}
