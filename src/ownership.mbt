// 型所有権管理ロジック

///|
/// 定義から型名を取得
fn get_definition_name(def : Definition) -> String {
  match def {
    Interface(iface) => iface.name
    Dictionary(dict) => dict.name
    Enum(e) => e.name
    Typedef(t) => t.name
    Partial(p) => p.target // PartialDef has `target` field
    InterfaceMixin(m) => m.name
    CallbackInterface(cb) => cb.name
    Includes(_) => "" // Includes has no type name
  }
}

///|
/// グローバル型所有権マップを構築（型名 -> 所有仕様名、最初の定義が優先）
/// Note: Partial定義は所有権を持たない（元の型を定義する仕様が所有者）
pub fn build_global_type_ownership(
  results : Array[SpecLoadResult],
) -> Array[(String, String)] {
  let ownership : Array[(String, String)] = []
  for result in results {
    if result.success {
      for def in result.definitions {
        // Skip Partial and Includes - they don't define new types
        match def {
          Partial(_) | Includes(_) => continue
          _ => ()
        }
        let type_name = get_definition_name(def)
        // Only register if not already owned (first wins)
        let mut already_owned = false
        for i = 0; i < ownership.length(); i = i + 1 {
          let (name, _) = ownership[i]
          if name == type_name {
            already_owned = true
            break
          }
        }
        if not(already_owned) && type_name != "" {
          ownership.push((type_name, result.spec_name))
        }
      }
    }
  }
  ownership
}

///|
/// 型の所有者を取得
fn get_type_owner(
  ownership : Array[(String, String)],
  type_name : String,
) -> String {
  for i = 0; i < ownership.length(); i = i + 1 {
    let (name, owner) = ownership[i]
    if name == type_name {
      return owner
    }
  }
  ""
}

///|
/// 仕様が所有する定義のみをフィルタリング
pub fn filter_definitions_by_owner(
  definitions : Array[Definition],
  spec_name : String,
  ownership : Array[(String, String)],
) -> Array[Definition] {
  let filtered : Array[Definition] = []
  for def in definitions {
    match def {
      // InterfaceMixin and Includes are always included (used for merging, not output)
      InterfaceMixin(_) => filtered.push(def)
      Includes(_) => filtered.push(def)
      // Partials are included if their target type is owned by this spec
      Partial(p) => {
        let target_owner = get_type_owner(ownership, p.target)
        if target_owner == spec_name {
          filtered.push(def)
        }
      }
      _ => {
        let type_name = get_definition_name(def)
        let owner = get_type_owner(ownership, type_name)

        // Include only if this spec owns the type
        if owner == spec_name {
          filtered.push(def)
        }
      }
    }
  }
  filtered
}
