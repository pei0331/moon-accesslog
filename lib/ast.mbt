///|
/// WIT (WebAssembly Interface Types) 1.0 abstract syntax tree.
///
/// Supports the core subset targeted by P0:
/// `package`, `interface`, `world`, `use`, `import`/`export`,
/// `record`/`variant`/`enum`/`flags`/`resource`/`type` aliases and `func` signatures.
/// Design inspired by bytecodealliance/wit-bindgen.

///|
/// A reference to a WIT type.
pub enum WitType {
  /// Named reference to a previously defined type.
  Name(String)
  /// `u8` — maps to MoonBit `Byte`.
  U8
  /// `u16` — maps to MoonBit `UInt16`.
  U16
  /// `u32` — maps to MoonBit `UInt`.
  U32
  /// `u64` — maps to MoonBit `UInt64`.
  U64
  /// `s8` — maps to MoonBit `Int` (widened, no `Int8` in core).
  S8
  /// `s16` — maps to MoonBit `Int16`.
  S16
  /// `s32` — maps to MoonBit `Int`.
  S32
  /// `s64` — maps to MoonBit `Int64`.
  S64
  /// `f32` — maps to MoonBit `Float`.
  F32
  /// `f64` — maps to MoonBit `Double`.
  F64
  /// `char` — maps to MoonBit `Char`.
  TChar
  /// `string` — maps to MoonBit `String`.
  TString
  /// `bool` — maps to MoonBit `Bool`.
  TBool
  /// `list<t>` — maps to MoonBit `List[T]`.
  List(WitType)
  /// `option<t>` — maps to MoonBit `Option[T]`.
  Option(WitType)
  /// `result<t, e>` — maps to MoonBit `Result[T, E]`.
  Result(WitType?, WitType?)
  /// `tuple<...>` — maps to a MoonBit tuple.
  Tuple(Array[WitType])
  /// `own<resource>`.
  Own(String)
  /// `borrow<resource>`.
  Borrow(String)
  /// `future<t>` asynchronous value handle.
  Future(WitType?)
  /// `stream<t>` asynchronous stream handle.
  Stream(WitType?)
}

///|
/// A named field with its type (record field or function parameter).
pub struct Field {
  name : String
  ty : WitType
}

///|
/// A variant case. `ty` is `None` for a unit case.
pub struct Case {
  name : String
  ty : WitType?
}

///|
/// A single unnamed result, or a named result (WIT named results).
pub enum FuncResult {
  Unnamed(WitType)
  Named(Field)
}

///|
/// `use path.{a, b as c}` declaration.
pub struct UseName {
  name : String
  asName : String?
}

///|
/// `use <path>.{a, b as c}` — re-exports types from an interface.
pub struct UseDecl {
  path : String
  names : Array[UseName]
}

///|
/// A `func` signature with parameters and results.
pub struct FuncSig {
  name : String
  params : Array[Field]
  results : Array[FuncResult]
}

///|
pub enum ResourceFuncKind {
  Constructor
  Static
  Method
}

///|
pub struct ResourceFunc {
  kind : ResourceFuncKind
  sig : FuncSig
}

///|
/// The kind of a named type definition.
pub enum TypeDefKind {
  /// `record` — a struct of named fields.
  Record(Array[Field])
  /// `variant` — a sum type with optional payloads.
  Variant(Array[Case])
  /// `enum` — a plain set of unit cases.
  Enum(Array[String])
  /// `flags` — a set of boolean flags.
  Flags(Array[String])
  /// `resource` — an opaque handle type.
  Resource(Array[ResourceFunc])
  /// `type X = <type>` — an alias.
  Alias(WitType)
}

///|
/// A named type definition.
pub struct TypeDef {
  name : String
  kind : TypeDefKind
}

///|
/// An item inside an `interface` (or an inline interface in a world).
pub enum InterfaceItem {
  Use(UseDecl)
  Type(TypeDef)
  Func(FuncSig)
}

///|
/// An `interface` definition.
pub struct Interface {
  name : String
  items : Array[InterfaceItem]
}

///|
/// An `import foo [as bar] [: interface {...}]` or `export ...` item.
pub struct ImpExp {
  name : String
  asName : String?
  /// `Some(iface)` when this is an inline `name: interface { ... }`.
  inline : Interface?
}

///|
/// An item inside a `world`.
pub enum WorldItem {
  Import(ImpExp)
  Export(ImpExp)
  /// A direct `import name: func(...);` declaration.
  ImportFunc(FuncSig)
  /// A direct `export name: func(...);` declaration.
  ExportFunc(FuncSig)
  /// A world composition declaration, optionally with renamed exports.
  Include(String, Array[UseName])
  Use(UseDecl)
}

///|
/// A `world` definition.
pub struct World {
  name : String
  items : Array[WorldItem]
}

///|
/// An item at the top level of a WIT document.
pub enum WitItem {
  Interface(Interface)
  World(World)
  Use(UseDecl)
}

///|
/// A parsed WIT document (the result of [`parse`](@wit)).
pub struct WitPackage {
  /// The package namespace (e.g. `docs` in `package docs:hello`).
  ns : String
  /// The package name (e.g. `hello` in `package docs:hello`).
  name : String
  version : String?
  items : Array[WitItem]
}

///|
/// Renders a WIT type reference back to WIT syntax.
pub fn WitType::to_string(self : WitType) -> String {
  match self {
    Name(n) => n
    U8 => "u8"
    U16 => "u16"
    U32 => "u32"
    U64 => "u64"
    S8 => "s8"
    S16 => "s16"
    S32 => "s32"
    S64 => "s64"
    F32 => "f32"
    F64 => "f64"
    TChar => "char"
    TString => "string"
    TBool => "bool"
    List(t) => "list<\{t.to_string()}>"
    Option(t) => "option<\{t.to_string()}>"
    Result(ok, err) => {
      let mut s = "result<\{slot_to_string(ok)}"
      match err {
        Some(e) => s = s + ", \{slot_to_string(Some(e))}"
        None => ()
      }
      s + ">"
    }
    Tuple(items) =>
      "tuple<\{join_strings(items.map(fn(t) { t.to_string() }), ", ")}>"
    Own(n) => "own<\{n}>"
    Borrow(n) => "borrow<\{n}>"
    Future(t) => "future<\{slot_to_string(t)}>"
    Stream(t) => "stream<\{slot_to_string(t)}>"
  }
}

///|
fn slot_to_string(slot : WitType?) -> String {
  match slot {
    Some(t) => t.to_string()
    None => "_"
  }
}

///|
fn join_strings(items : Array[String], sep : String) -> String {
  let mut s = ""
  let mut first = true
  for item in items {
    if !first {
      s = s + sep
    }
    s = s + item
    first = false
  }
  s
}

///|
fn indent_lines(text : String, prefix : String) -> String {
  let mut s = prefix
  for ch in text {
    s = s + ch.to_string()
    if ch == '\n' {
      s = s + prefix
    }
  }
  s
}

///|
pub fn Field::to_string(self : Field) -> String {
  "\{self.name}: \{self.ty.to_string()}"
}

///|
pub fn Case::to_string(self : Case) -> String {
  match self.ty {
    Some(t) => "\{self.name}(\{t.to_string()})"
    None => self.name
  }
}

///|
pub fn FuncResult::to_string(self : FuncResult) -> String {
  match self {
    Unnamed(t) => t.to_string()
    Named(f) => f.to_string()
  }
}

///|
pub fn UseDecl::to_string(self : UseDecl) -> String {
  let mut s = "use \{self.path}."
  if self.names.length() == 0 {
    s = s + "*"
  } else {
    s = s + "{\{join_strings(self.names.map(fn(n) { n.to_string() }), ", ")}"
    s = s + "}"
  }
  s + ";"
}

///|
pub fn UseName::to_string(self : UseName) -> String {
  match self.asName {
    Some(a) => "\{self.name} as \{a}"
    None => self.name
  }
}

///|
pub fn TypeDef::to_string(self : TypeDef) -> String {
  match self.kind {
    Record(fields) => {
      let mut s = "record \{self.name} {\n"
      for f in fields {
        s = s + "  \{f.to_string()}\n"
      }
      s + "}"
    }
    Variant(cases) => {
      let mut s = "variant \{self.name} {\n"
      for c in cases {
        s = s + "  \{c.to_string()}\n"
      }
      s + "}"
    }
    Enum(names) => {
      let mut s = "enum \{self.name} {\n"
      for n in names {
        s = s + "  \{n}\n"
      }
      s + "}"
    }
    Flags(names) => {
      let mut s = "flags \{self.name} {\n"
      for n in names {
        s = s + "  \{n}\n"
      }
      s + "}"
    }
    Resource(funcs) => {
      if funcs.length() == 0 {
        return "resource \{self.name};"
      }
      let mut s = "resource \{self.name} {\n"
      for f in funcs {
        let prefix = match f.kind {
          Constructor => "constructor\{f.sig.signature_to_string()}"
          Static => "static \{f.sig.to_string()}"
          Method => f.sig.to_string()
        }
        s = s + "  \{prefix};\n"
      }
      s + "}"
    }
    Alias(t) => "type \{self.name} = \{t.to_string()};"
  }
}

///|
pub fn FuncSig::to_string(self : FuncSig) -> String {
  "\{self.name}: \{self.type_to_string()}"
}

///|
fn FuncSig::type_to_string(self : FuncSig) -> String {
  "func\{self.signature_to_string()}"
}

///|
fn FuncSig::signature_to_string(self : FuncSig) -> String {
  let mut s = "("
  s = s + join_strings(self.params.map(fn(p) { p.to_string() }), ", ")
  s = s + ")"
  if self.results.length() != 0 {
    s = s + " -> " + func_results_to_string(self.results)
  }
  s
}

///|
fn func_results_to_string(results : Array[FuncResult]) -> String {
  if results.length() == 1 {
    match results[0] {
      Unnamed(t) => return t.to_string()
      _ => ()
    }
  }
  "(\{join_strings(results.map(fn(r) { r.to_string() }), ", ")})"
}

///|
pub fn InterfaceItem::to_string(self : InterfaceItem) -> String {
  match self {
    Use(u) => u.to_string()
    Type(t) => t.to_string()
    Func(f) => f.to_string()
  }
}

///|
pub fn Interface::to_string(self : Interface) -> String {
  let mut s = "interface \{self.name} {\n"
  for item in self.items {
    s = s + indent_lines(item.to_string(), "  ") + "\n"
  }
  s + "}"
}

///|
pub fn ImpExp::to_string(self : ImpExp) -> String {
  let mut s = self.name
  match self.asName {
    Some(a) => s = s + " as \{a}"
    None => ()
  }
  match self.inline {
    Some(iface) => {
      s = s + ": interface {\n"
      for item in iface.items {
        s = s + indent_lines(item.to_string(), "  ") + "\n"
      }
      s = s + "}"
    }
    None => s = s + ";"
  }
  s
}

///|
pub fn WorldItem::to_string(self : WorldItem) -> String {
  match self {
    Import(imp) => "import \{imp.to_string()}"
    Export(exp) => "export \{exp.to_string()}"
    ImportFunc(f) => "import \{f.to_string()};"
    ExportFunc(f) => "export \{f.to_string()};"
    Include(path, names) => {
      let mut s = "include \{path}"
      if names.length() != 0 {
        s = s +
          " with {\{join_strings(names.map(fn(n) { n.to_string() }), ", ")}}"
      }
      s + ";"
    }
    Use(u) => u.to_string()
  }
}

///|
pub fn World::to_string(self : World) -> String {
  let mut s = "world \{self.name} {\n"
  for item in self.items {
    s = s + indent_lines(item.to_string(), "  ") + "\n"
  }
  s + "}"
}

///|
pub fn WitItem::to_string(self : WitItem) -> String {
  match self {
    Interface(i) => i.to_string()
    World(w) => w.to_string()
    Use(u) => u.to_string()
  }
}

///|
pub fn WitPackage::to_string(self : WitPackage) -> String {
  let mut s = "package \{self.ns}:\{self.name}"
  match self.version {
    Some(v) => s = s + "@\{v}"
    None => ()
  }
  s = s + ";\n"
  for item in self.items {
    s = s + item.to_string() + "\n"
  }
  s
}
