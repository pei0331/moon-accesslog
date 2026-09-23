///|
/// Compatibility severity, ordered by impact rather than parser detail.
pub enum Severity {
  Compatible
  Breaking
}

///|
/// One API change found between two WIT packages.
pub struct Change {
  severity : Severity
  subject : String
  detail : String
}

///|
/// A complete compatibility report.
pub struct Report {
  changes : Array[Change]
}

///|
/// Compare two WIT packages. Removed or changed declarations are breaking;
/// additions are reported as compatible. This conservative policy treats
/// imports and exports uniformly because the consumer direction is not known.
pub fn compare(old : WitPackage, new : WitPackage) -> Report {
  let changes : Array[Change] = []
  if old.ns != new.ns || old.name != new.name {
    changes.push(Change::{
      severity: Breaking,
      subject: "package",
      detail: "package identity changed from \{old.ns}:\{old.name} to \{new.ns}:\{new.name}",
    })
  }
  let old_items = collect_items(old)
  let new_items = collect_items(new)
  for item in old_items {
    let subject = item.0
    let signature = item.1
    match lookup(new_items, subject) {
      Some(next) =>
        if signature != next {
          changes.push(Change::{
            severity: Breaking,
            subject,
            detail: "declaration changed",
          })
        }
      None =>
        changes.push(Change::{
          severity: Breaking,
          subject,
          detail: "declaration was removed",
        })
    }
  }
  for item in new_items {
    let subject = item.0
    if !contains(old_items, subject) {
      changes.push(Change::{
        severity: Compatible,
        subject,
        detail: "declaration was added",
      })
    }
  }
  Report::{ changes, }
}

///|
/// Returns true if the report contains a breaking change.
pub fn Report::has_breaking(self : Report) -> Bool {
  self.changes.any(change => change.severity is Breaking)
}

///|
/// Render a deterministic, human-readable report.
pub fn Report::to_string(self : Report) -> String {
  if self.changes.is_empty() {
    return "Compatible: no public API changes detected."
  }
  let mut output = ""
  for change in self.changes {
    let label = match change.severity {
      Breaking => "BREAKING"
      Compatible => "ADDITIVE"
    }
    output = output + "[\{label}] \{change.subject}: \{change.detail}\n"
  }
  output
}

///|
fn collect_items(pkg : WitPackage) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  for item in pkg.items {
    match item {
      Interface(iface) =>
        for entry in iface.items {
          match entry {
            Func(sig) =>
              result.push(
                (
                  "interface \{iface.name} function \{sig.name}",
                  sig.to_string(),
                ),
              )
            Type(def) =>
              result.push(
                ("interface \{iface.name} type \{def.name}", def.to_string()),
              )
            Use(decl) =>
              result.push(
                ("interface \{iface.name} use \{decl.path}", decl.to_string()),
              )
          }
        }
      World(world) =>
        for entry in world.items {
          match entry {
            Import(item) =>
              result.push(
                (world_key(world.name, "import", item.name), item.to_string()),
              )
            Export(item) =>
              result.push(
                (world_key(world.name, "export", item.name), item.to_string()),
              )
            ImportFunc(sig) =>
              result.push(
                (world_key(world.name, "import", sig.name), sig.to_string()),
              )
            ExportFunc(sig) =>
              result.push(
                (world_key(world.name, "export", sig.name), sig.to_string()),
              )
            Include(path, renames) =>
              result.push(
                (
                  "world \{world.name} include \{path}",
                  "include \{path} \{join_strings(renames.map(rename => rename.to_string()), ",")}",
                ),
              )
            Use(decl) =>
              result.push(
                ("world \{world.name} use \{decl.path}", decl.to_string()),
              )
          }
        }
      Use(decl) => result.push(("package use \{decl.path}", decl.to_string()))
    }
  }
  result
}

///|
fn world_key(world : String, direction : String, name : String) -> String {
  "world \{world} \{direction} \{name}"
}

///|
fn lookup(items : Array[(String, String)], key : String) -> String? {
  for item in items {
    let name = item.0
    let value = item.1
    if name == key {
      return Some(value)
    }
  }
  None
}

///|
fn contains(items : Array[(String, String)], key : String) -> Bool {
  for item in items {
    let name = item.0
    if name == key {
      return true
    }
  }
  false
}
