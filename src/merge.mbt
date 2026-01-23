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
  definitions.iter().each(fn(def) {
    match def {
      Interface(iface) =>
        // Merge or add interface using helper
        merge_or_add_interface(interfaces, iface)
      Dictionary(dict) =>
        // Merge or add dictionary using helper
        merge_or_add_dictionary(dictionaries, dict)
      Partial(partial) => partials.push(partial)
      Enum(e) =>
        // Only add enum if not already seen
        if not(seen_enums.contains(e.name)) {
          seen_enums.push(e.name)
          others.push(def)
        }
      Typedef(t) =>
        // Only add typedef if not already seen
        if not(seen_typedefs.contains(t.name)) {
          seen_typedefs.push(t.name)
          others.push(def)
        }
      CallbackInterface(cb) =>
        // Only add callback interface if not already seen
        if not(seen_callbacks.contains(cb.name)) {
          seen_callbacks.push(cb.name)
          others.push(def)
        }
      InterfaceMixin(mix_def) =>
        // Merge or add mixin using helper
        merge_or_add_mixin(mixins, mix_def)
      Includes(incl) => includes_list.push(incl)
    }
  })

  // Step 2: Merge partial members into their target interfaces/dictionaries
  partials.iter().each(fn(partial) {
    let target_name = partial.target
    // Convert partial to interface and merge
    let partial_as_iface : InterfaceDef = {
      name: target_name,
      members: partial.members,
      inheritance: None,
      extended_attrs: [],
    }
    merge_or_add_interface(interfaces, partial_as_iface)
  })

  // Step 3: Merge mixin members into interfaces based on includes statements
  includes_list.iter().each(fn(incl) {
    let target_name = incl.target
    let mixin_name = incl.includes

    // Find the mixin members
    let mixin_members = mixins.iter().fold(
      init=([] : Array[InterfaceMember]),
      fn(found, entry) {
        if found.length() > 0 {
          return found
        }
        let (name, mix_def) = entry
        if name == mixin_name { mix_def.members } else { found }
      },
    )

    // Skip if mixin not found (might be in another spec)
    if mixin_members.length() == 0 {
      return
    }

    // Find target interface and merge mixin members
    merge_mixin_into_interface(interfaces, target_name, mixin_members, mixin_name)
  })

  // Step 4: Resolve inheritance for interfaces
  resolve_interface_inheritance(interfaces)

  // Step 5: Resolve inheritance for dictionaries
  resolve_dictionary_inheritance(dictionaries)

  // Step 6: Build result array
  let result : Array[Definition] = others.copy()

  // Add dictionaries
  dictionaries.iter().each(fn(entry) { result.push(Dictionary(entry.1)) })

  // Add interfaces
  interfaces.iter().each(fn(entry) { result.push(Interface(entry.1)) })
  result
}

///|
/// Interface を配列にマージまたは追加
fn merge_or_add_interface(
  interfaces : Array[(String, InterfaceDef)],
  iface : InterfaceDef,
) -> Unit {
  for i = 0; i < interfaces.length(); i = i + 1 {
    let (name, existing) = interfaces[i]
    if name == iface.name {
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
      return
    }
  }
  interfaces.push((iface.name, iface))
}

///|
/// Dictionary を配列にマージまたは追加
fn merge_or_add_dictionary(
  dictionaries : Array[(String, DictionaryDef)],
  dict : DictionaryDef,
) -> Unit {
  for i = 0; i < dictionaries.length(); i = i + 1 {
    let (name, existing) = dictionaries[i]
    if name == dict.name {
      let merged_members = merge_dictionary_members(existing.members, dict.members)
      let merged_dict : DictionaryDef = {
        name: existing.name,
        members: merged_members,
        inheritance: match existing.inheritance {
          Some(_) => existing.inheritance
          None => dict.inheritance
        },
      }
      dictionaries[i] = (name, merged_dict)
      return
    }
  }
  dictionaries.push((dict.name, dict))
}

///|
/// Mixin メンバーを Interface にマージ
fn merge_mixin_into_interface(
  interfaces : Array[(String, InterfaceDef)],
  target_name : String,
  mixin_members : Array[InterfaceMember],
  mixin_name : String,
) -> Unit {
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
      return
    }
  }
}

///|
/// Mixin を配列にマージまたは追加
fn merge_or_add_mixin(
  mixins : Array[(String, InterfaceMixinDef)],
  mix_def : InterfaceMixinDef,
) -> Unit {
  for i = 0; i < mixins.length(); i = i + 1 {
    let (name, existing) = mixins[i]
    if name == mix_def.name {
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
      return
    }
  }
  mixins.push((mix_def.name, mix_def))
}

///|
/// Interface メンバーをマージ（重複検出付き）
fn merge_interface_members(
  existing : Array[InterfaceMember],
  new_members : Array[InterfaceMember],
  _target_name : String,
) -> Array[InterfaceMember] {
  // Start with existing members
  let result : Array[InterfaceMember] = existing.copy()
  // Add new members, checking for duplicates
  new_members.iter().each(fn(new_mem) {
    let new_name = get_member_name(new_mem)
    let is_duplicate = new_name != "" &&
      existing.iter().any(fn(m) { get_member_name(m) == new_name })
    if not(is_duplicate) {
      result.push(new_mem)
    }
  })
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
  // Copy existing members (with duplicate check using fold)
  let result : Array[DictionaryMember] = existing.iter().fold(
    init=Array::new(),
    fn(result : Array[DictionaryMember], mem) {
      if not(result.iter().any(fn(r) { r.name == mem.name })) {
        result.push(mem)
      }
      result
    },
  )
  // Add new members, checking for duplicates
  new_members.iter().fold(init=result, fn(result, new_mem) {
    if not(result.iter().any(fn(r) { r.name == new_mem.name })) {
      result.push(new_mem)
    }
    result
  })
}

///|
/// インターフェースの継承関係を解決
/// 親のメンバーを子に展開する（循環継承の検出付き）
fn resolve_interface_inheritance(
  interfaces : Array[(String, InterfaceDef)],
) -> Unit {
  // 元の定義をコピー（継承解決前の状態を保持）
  let original = interfaces.copy()

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
  if visited.iter().any(fn(v) { v == parent_name }) {
    println(
      "Warning: Circular inheritance detected: " + parent_name + " - skipping",
    )
    return []
  }

  // 親インターフェースを検索
  let parent_iface = interfaces.iter().fold(
    init=(None : InterfaceDef?),
    fn(found, entry) {
      match found {
        Some(_) => found
        None => if entry.0 == parent_name { Some(entry.1) } else { None }
      }
    },
  )

  // 親が見つからない場合は空配列
  match parent_iface {
    None => []
    Some(iface) => {
      // 親のさらに親のメンバーを再帰的に収集
      let grandparent_members = match iface.inheritance {
        Some(grandparent_name) => {
          let new_visited = visited.copy()
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
      let result = grandparent_members.iter().fold(
        init=Array::new(),
        fn(acc : Array[InterfaceMember], mem) {
          let mem_name = get_interface_member_name(mem)
          if not(acc.iter().any(fn(e) { get_interface_member_name(e) == mem_name })) {
            acc.push(mem)
          }
          acc
        },
      )
      // 親のメンバーを追加（祖父と重複する場合は親を優先）
      iface.members.iter().fold(init=result, fn(acc, mem) {
        let mem_name = get_interface_member_name(mem)
        if not(acc.iter().any(fn(e) { get_interface_member_name(e) == mem_name })) {
          acc.push(mem)
        }
        acc
      })
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
  let original = dictionaries.copy()

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
  if visited.iter().any(fn(v) { v == parent_name }) {
    println(
      "Warning: Circular inheritance detected in dictionary: " +
      parent_name +
      " - skipping",
    )
    return []
  }

  // 親 dictionary を検索
  let parent_dict = dictionaries.iter().fold(
    init=(None : DictionaryDef?),
    fn(found, entry) {
      match found {
        Some(_) => found
        None => if entry.0 == parent_name { Some(entry.1) } else { None }
      }
    },
  )

  // 親が見つからない場合は空配列
  match parent_dict {
    None => []
    Some(dict) => {
      // 親のさらに親のメンバーを再帰的に収集
      let grandparent_members = match dict.inheritance {
        Some(grandparent_name) => {
          let new_visited = visited.copy()
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
      let result = grandparent_members.iter().fold(
        init=Array::new(),
        fn(acc : Array[DictionaryMember], mem) {
          if not(acc.iter().any(fn(e) { e.name == mem.name })) {
            acc.push(mem)
          }
          acc
        },
      )
      // 親のメンバーを追加（祖父と重複する場合は親を優先）
      dict.members.iter().fold(init=result, fn(acc, mem) {
        if not(acc.iter().any(fn(e) { e.name == mem.name })) {
          acc.push(mem)
        }
        acc
      })
    }
  }
}
