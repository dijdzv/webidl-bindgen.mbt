// 定義マージ・継承解決ロジック

///|
/// Partial 定義をマージして統合された定義配列を返す
/// 継承関係も解決して親メンバーを子に展開する
pub fn merge_definitions(definitions : Array[Definition]) -> Array[Definition] {
  // Step 1: Collect all non-partial definitions into a map by name
  // Deduplicate interfaces and dictionaries by merging members
  let interfaces : Array[(String, InterfaceDef)] = []
  let dictionaries : Array[(String, DictionaryDef)] = []
  let mixins : Array[(String, InterfaceMixinDef)] = [] // Collect mixins
  let includes_list : Array[IncludesDef] = [] // Collect includes statements
  let others : Array[Definition] = []
  let partials : Array[PartialDef] = []
  let seen_enums : Array[String] = [] // Track seen enum names
  let seen_typedefs : Array[String] = [] // Track seen typedef names
  let seen_callbacks : Array[String] = [] // Track seen callback interface names
  for def in definitions {
    match def {
      Interface(iface) => {
        // Check if interface already exists
        let mut found = false
        for i = 0; i < interfaces.length(); i = i + 1 {
          let (name, existing) = interfaces[i]
          if name == iface.name {
            // Merge members from duplicate interface
            let merged_members = merge_interface_members(
              existing.members,
              iface.members,
              iface.name,
            )
            let merged_iface : InterfaceDef = {
              name: existing.name,
              members: merged_members,
              inheritance: match existing.inheritance {
                Some(_) => existing.inheritance
                None => iface.inheritance
              },
              extended_attrs: existing.extended_attrs,
            }
            interfaces[i] = (name, merged_iface)
            found = true
            break
          }
        }
        if not(found) {
          interfaces.push((iface.name, iface))
        }
      }
      Dictionary(dict) => {
        // Check if dictionary already exists
        let mut found = false
        for i = 0; i < dictionaries.length(); i = i + 1 {
          let (name, existing) = dictionaries[i]
          if name == dict.name {
            // Merge members from duplicate dictionary
            let merged_members = merge_dictionary_members(
              existing.members,
              dict.members,
            )
            let merged_dict : DictionaryDef = {
              name: existing.name,
              members: merged_members,
              inheritance: match existing.inheritance {
                Some(_) => existing.inheritance
                None => dict.inheritance
              },
            }
            dictionaries[i] = (name, merged_dict)
            found = true
            break
          }
        }
        if not(found) {
          dictionaries.push((dict.name, dict))
        }
      }
      Partial(partial) => partials.push(partial)
      Enum(e) =>
        // Only add enum if not already seen
        if not(array_contains(seen_enums, e.name)) {
          seen_enums.push(e.name)
          others.push(def)
        }
      Typedef(t) =>
        // Only add typedef if not already seen
        if not(array_contains(seen_typedefs, t.name)) {
          seen_typedefs.push(t.name)
          others.push(def)
        }
      CallbackInterface(cb) =>
        // Only add callback interface if not already seen
        if not(array_contains(seen_callbacks, cb.name)) {
          seen_callbacks.push(cb.name)
          others.push(def)
        }
      InterfaceMixin(mix_def) => {
        // Collect mixin for later merging
        let mut found = false
        for i = 0; i < mixins.length(); i = i + 1 {
          let (name, existing) = mixins[i]
          if name == mix_def.name {
            // Merge members from duplicate mixin
            let merged_members = merge_interface_members(
              existing.members,
              mix_def.members,
              mix_def.name,
            )
            let merged_mixin : InterfaceMixinDef = {
              name: existing.name,
              members: merged_members,
            }
            mixins[i] = (name, merged_mixin)
            found = true
            break
          }
        }
        if not(found) {
          mixins.push((mix_def.name, mix_def))
        }
      }
      Includes(incl) => includes_list.push(incl)
    }
  }

  // Step 2: Merge partial members into their target interfaces/dictionaries
  for partial in partials {
    let target_name = partial.target

    // Try to find and merge with an interface
    let mut found = false
    for i = 0; i < interfaces.length(); i = i + 1 {
      let (name, iface) = interfaces[i]
      if name == target_name {
        // Merge members (check for duplicates)
        let merged_members = merge_interface_members(
          iface.members,
          partial.members,
          target_name,
        )
        let merged_iface : InterfaceDef = {
          name: iface.name,
          members: merged_members,
          inheritance: iface.inheritance,
          extended_attrs: iface.extended_attrs,
        }
        interfaces[i] = (name, merged_iface)
        found = true
        break
      }
    }

    // If not found as interface, create a new interface from partial
    if not(found) {
      let new_iface : InterfaceDef = {
        name: target_name,
        members: partial.members,
        inheritance: None,
        extended_attrs: [],
      }
      interfaces.push((target_name, new_iface))
    }
  }

  // Step 3: Merge mixin members into interfaces based on includes statements
  for incl in includes_list {
    let target_name = incl.target
    let mixin_name = incl.includes

    // Find the mixin
    let mut mixin_members : Array[InterfaceMember] = []
    for i = 0; i < mixins.length(); i = i + 1 {
      let (name, mix_def) = mixins[i]
      if name == mixin_name {
        mixin_members = mix_def.members
        break
      }
    }

    // Skip if mixin not found (might be in another spec)
    if mixin_members.length() == 0 {
      continue
    }

    // Find target interface and merge mixin members
    for i = 0; i < interfaces.length(); i = i + 1 {
      let (name, iface) = interfaces[i]
      if name == target_name {
        let merged_members = merge_interface_members(
          iface.members,
          mixin_members,
          target_name + " (from mixin " + mixin_name + ")",
        )
        let merged_iface : InterfaceDef = {
          name: iface.name,
          members: merged_members,
          inheritance: iface.inheritance,
          extended_attrs: iface.extended_attrs,
        }
        interfaces[i] = (name, merged_iface)
        break
      }
    }
  }

  // Step 4: Resolve inheritance for interfaces
  resolve_interface_inheritance(interfaces)

  // Step 5: Resolve inheritance for dictionaries
  resolve_dictionary_inheritance(dictionaries)

  // Step 6: Build result array
  let result : Array[Definition] = []

  // Add other definitions first (enums, typedefs)
  for def in others {
    result.push(def)
  }

  // Add dictionaries
  for i = 0; i < dictionaries.length(); i = i + 1 {
    let (_, dict) = dictionaries[i]
    result.push(Dictionary(dict))
  }

  // Add interfaces
  for i = 0; i < interfaces.length(); i = i + 1 {
    let (_, iface) = interfaces[i]
    result.push(Interface(iface))
  }
  result
}

///|
/// Interface メンバーをマージ（重複検出付き）
fn merge_interface_members(
  existing : Array[InterfaceMember],
  new_members : Array[InterfaceMember],
  _target_name : String,
) -> Array[InterfaceMember] {
  let result : Array[InterfaceMember] = []

  // Copy existing members
  for mem in existing {
    result.push(mem)
  }

  // Add new members, checking for duplicates
  for new_mem in new_members {
    let new_name = get_member_name(new_mem)
    let mut is_duplicate = false
    for existing_mem in existing {
      if get_member_name(existing_mem) == new_name && new_name != "" {
        // Duplicate detected - skip silently (expected during inheritance)
        is_duplicate = true
        break
      }
    }
    if not(is_duplicate) {
      result.push(new_mem)
    }
  }
  result
}

///|
/// メンバーの名前を取得
fn get_member_name(mem : InterfaceMember) -> String {
  match mem {
    Operation(op) => op.name
    Attribute(attr) => attr.name
    Const(c) => c.name
    Constructor(_) => "" // Constructors don't have names
    Maplike(_) => "" // Maplike is a type-level feature, not a named member
    Setlike(_) => "" // Setlike is a type-level feature, not a named member
  }
}

///|
/// Dictionary メンバーをマージ（重複検出付き）
fn merge_dictionary_members(
  existing : Array[DictionaryMember],
  new_members : Array[DictionaryMember],
) -> Array[DictionaryMember] {
  let result : Array[DictionaryMember] = []

  // Copy existing members (with duplicate check)
  for mem in existing {
    let mut is_duplicate = false
    for r in result {
      if r.name == mem.name {
        is_duplicate = true
        break
      }
    }
    if not(is_duplicate) {
      result.push(mem)
    }
  }

  // Add new members, checking for duplicates
  for new_mem in new_members {
    let mut is_duplicate = false
    for r in result {
      if r.name == new_mem.name {
        is_duplicate = true
        break
      }
    }
    if not(is_duplicate) {
      result.push(new_mem)
    }
  }
  result
}

///|
/// インターフェースの継承関係を解決
/// 親のメンバーを子に展開する（循環継承の検出付き）
fn resolve_interface_inheritance(
  interfaces : Array[(String, InterfaceDef)],
) -> Unit {
  // 元の定義をコピー（継承解決前の状態を保持）
  let original : Array[(String, InterfaceDef)] = []
  for i = 0; i < interfaces.length(); i = i + 1 {
    original.push(interfaces[i])
  }

  // 各インターフェースの継承を解決（元の定義から収集）
  let mut resolved_count = 0
  for i = 0; i < interfaces.length(); i = i + 1 {
    let (name, iface) = interfaces[i]
    match iface.inheritance {
      Some(parent_name) => {
        // 親のメンバーを収集（元の定義から、循環参照チェック付き）
        let visited : Array[String] = [name]
        let inherited_members = collect_inherited_interface_members(
          original, // 元の定義を使う（展開前）
          parent_name,
          visited,
        )
        if inherited_members.length() > 0 {
          resolved_count = resolved_count + 1
        }
        // 親のメンバーを子の先頭に追加（子のメンバーが優先）
        let combined = merge_interface_members(
          inherited_members,
          iface.members,
          name + " (inherited)",
        )
        let new_iface : InterfaceDef = {
          name: iface.name,
          members: combined,
          inheritance: iface.inheritance,
          extended_attrs: iface.extended_attrs,
        }
        interfaces[i] = (name, new_iface)
      }
      None => ()
    }
  }
  if resolved_count > 0 {
    println(
      "Resolved " +
      resolved_count.to_string() +
      " interface inheritance relationships",
    )
  }
}

///|
/// 親インターフェースのメンバーを再帰的に収集
fn collect_inherited_interface_members(
  interfaces : Array[(String, InterfaceDef)],
  parent_name : String,
  visited : Array[String],
) -> Array[InterfaceMember] {
  // 循環継承の検出
  for v in visited {
    if v == parent_name {
      println(
        "Warning: Circular inheritance detected: " + parent_name + " - skipping",
      )
      return []
    }
  }

  // 親インターフェースを検索
  let mut parent_iface : InterfaceDef? = None
  for i = 0; i < interfaces.length(); i = i + 1 {
    let (name, iface) = interfaces[i]
    if name == parent_name {
      parent_iface = Some(iface)
      break
    }
  }

  // 親が見つからない場合は空配列
  match parent_iface {
    None => []
    Some(iface) => {
      // 親のさらに親のメンバーを再帰的に収集
      let grandparent_members = match iface.inheritance {
        Some(grandparent_name) => {
          let new_visited : Array[String] = []
          for v in visited {
            new_visited.push(v)
          }
          new_visited.push(parent_name)
          collect_inherited_interface_members(
            interfaces,
            grandparent_name,
            new_visited,
          )
        }
        None => []
      }

      // 祖先のメンバー + 親自身のメンバー（重複チェック付き）
      let result : Array[InterfaceMember] = []
      for mem in grandparent_members {
        // 祖父母からの継承で重複がある場合はスキップ
        let mem_name = get_interface_member_name(mem)
        let mut is_duplicate = false
        for existing in result {
          if get_interface_member_name(existing) == mem_name {
            is_duplicate = true
            break
          }
        }
        if not(is_duplicate) {
          result.push(mem)
        }
      }
      // 親のメンバーを追加（祖父と重複する場合は親を優先）
      for mem in iface.members {
        let mem_name = get_interface_member_name(mem)
        let mut is_duplicate = false
        for existing in result {
          if get_interface_member_name(existing) == mem_name {
            is_duplicate = true
            break
          }
        }
        if not(is_duplicate) {
          result.push(mem)
        }
      }
      result
    }
  }
}

///|
/// Interface メンバーの名前を取得
fn get_interface_member_name(m : InterfaceMember) -> String {
  match m {
    Operation(op) => op.name
    Attribute(attr) => attr.name
    Const(c) => c.name
    Constructor(_) => "constructor"
    Maplike(_) => "maplike"
    Setlike(_) => "setlike"
  }
}

///|
/// Dictionary の継承関係を解決
fn resolve_dictionary_inheritance(
  dictionaries : Array[(String, DictionaryDef)],
) -> Unit {
  // 元の定義をコピー（継承解決前の状態を保持）
  let original : Array[(String, DictionaryDef)] = []
  for i = 0; i < dictionaries.length(); i = i + 1 {
    original.push(dictionaries[i])
  }

  // 各 dictionary の継承を解決（元の定義から収集）
  for i = 0; i < dictionaries.length(); i = i + 1 {
    let (name, dict) = dictionaries[i]
    match dict.inheritance {
      Some(parent_name) => {
        // 親のメンバーを収集（元の定義から、循環参照チェック付き）
        let visited : Array[String] = [name]
        let inherited_members = collect_inherited_dictionary_members(
          original, // 元の定義を使う（展開前）
          parent_name,
          visited,
        )
        // 親のメンバーを子の先頭に追加
        let combined = merge_dictionary_members(inherited_members, dict.members)
        let new_dict : DictionaryDef = {
          name: dict.name,
          members: combined,
          inheritance: dict.inheritance,
        }
        dictionaries[i] = (name, new_dict)
      }
      None => ()
    }
  }
}

///|
/// 親 dictionary のメンバーを再帰的に収集
fn collect_inherited_dictionary_members(
  dictionaries : Array[(String, DictionaryDef)],
  parent_name : String,
  visited : Array[String],
) -> Array[DictionaryMember] {
  // 循環継承の検出
  for v in visited {
    if v == parent_name {
      println(
        "Warning: Circular inheritance detected in dictionary: " +
        parent_name +
        " - skipping",
      )
      return []
    }
  }

  // 親 dictionary を検索
  let mut parent_dict : DictionaryDef? = None
  for i = 0; i < dictionaries.length(); i = i + 1 {
    let (name, dict) = dictionaries[i]
    if name == parent_name {
      parent_dict = Some(dict)
      break
    }
  }

  // 親が見つからない場合は空配列
  match parent_dict {
    None => []
    Some(dict) => {
      // 親のさらに親のメンバーを再帰的に収集
      let grandparent_members = match dict.inheritance {
        Some(grandparent_name) => {
          let new_visited : Array[String] = []
          for v in visited {
            new_visited.push(v)
          }
          new_visited.push(parent_name)
          collect_inherited_dictionary_members(
            dictionaries,
            grandparent_name,
            new_visited,
          )
        }
        None => []
      }

      // 祖先のメンバー + 親自身のメンバー（重複チェック付き）
      let result : Array[DictionaryMember] = []
      for mem in grandparent_members {
        // 祖父母からの継承で重複がある場合はスキップ
        let mut is_duplicate = false
        for existing in result {
          if existing.name == mem.name {
            is_duplicate = true
            break
          }
        }
        if not(is_duplicate) {
          result.push(mem)
        }
      }
      // 親のメンバーを追加（祖父と重複する場合は親を優先）
      for mem in dict.members {
        let mut is_duplicate = false
        for existing in result {
          if existing.name == mem.name {
            is_duplicate = true
            break
          }
        }
        if not(is_duplicate) {
          result.push(mem)
        }
      }
      result
    }
  }
}
