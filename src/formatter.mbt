// コード出力フォーマッター

///|
/// WebIDL で定義される型名を収集
fn collect_defined_types(definitions : Array[Definition]) -> Array[String] {
  let types : Array[String] = []
  for def in definitions {
    match def {
      Interface(iface) => types.push(iface.name)
      Dictionary(dict) => types.push(dict.name)
      Enum(e) => types.push(e.name)
      Typedef(t) => types.push(t.name)
      CallbackInterface(cb) => types.push(cb.name)
      _ => ()
    }
  }
  types
}

///|
/// 定義内で参照されている型名を収集
fn collect_referenced_types(definitions : Array[Definition]) -> Array[String] {
  let refs : Array[String] = []
  for def in definitions {
    match def {
      Interface(iface) =>
        for mem in iface.members {
          collect_types_from_member(mem, refs)
        }
      Dictionary(dict) =>
        for mem in dict.members {
          collect_types_from_idl_type(mem.idl_type, refs)
        }
      Typedef(t) => collect_types_from_idl_type(t.idl_type, refs)
      Partial(p) =>
        for mem in p.members {
          collect_types_from_member(mem, refs)
        }
      _ => ()
    }
  }
  refs
}

///|
/// InterfaceMember から型を収集
fn collect_types_from_member(
  mem : InterfaceMember,
  refs : Array[String],
) -> Unit {
  match mem {
    Operation(op) => {
      collect_types_from_idl_type(op.return_type, refs)
      for arg in op.arguments {
        collect_types_from_idl_type(arg.idl_type, refs)
      }
    }
    Attribute(attr) => collect_types_from_idl_type(attr.idl_type, refs)
    Const(c) => collect_types_from_idl_type(c.idl_type, refs)
    Constructor(ctor) =>
      for arg in ctor.arguments {
        collect_types_from_idl_type(arg.idl_type, refs)
      }
    Maplike(m) => {
      collect_types_from_idl_type(m.key_type, refs)
      collect_types_from_idl_type(m.value_type, refs)
    }
    Setlike(s) => collect_types_from_idl_type(s.value_type, refs)
  }
}

///|
/// IdlType から Named 型を収集
fn collect_types_from_idl_type(t : IdlType, refs : Array[String]) -> Unit {
  match t {
    Named(name) => if not(array_contains(refs, name)) { refs.push(name) }
    Nullable(inner) => collect_types_from_idl_type(inner, refs)
    Sequence(inner) => collect_types_from_idl_type(inner, refs)
    Promise(inner) => collect_types_from_idl_type(inner, refs)
    Union(types) =>
      for ut in types {
        collect_types_from_idl_type(ut, refs)
      }
    _ => ()
  }
}

///|
/// 配列に値が含まれるか
fn array_contains(arr : Array[String], val : String) -> Bool {
  for item in arr {
    if item == val {
      return true
    }
  }
  false
}

///|
/// 未定義の外部型を抽出（ownership map から定義済み型を除外するバージョン）
pub fn collect_external_types_with_ownership(
  definitions : Array[Definition],
  ownership : Array[(String, String)],
) -> Array[String] {
  let referenced = collect_referenced_types(definitions)
  let undefined : Array[String] = []

  // 組み込み型は除外
  let builtins = [
    "JsValue", "Int", "Int64", "Double", "Bool", "String", "Unit", "Bytes",
  ]
  for ref_type in referenced {
    // 小文字始まりは除外 (object など無効な型名)
    let first_char = get_first_char(ref_type)
    let is_lowercase = first_char >= 'a' && first_char <= 'z'

    // ownership map で定義済みかチェック
    let mut is_defined = false
    for i = 0; i < ownership.length(); i = i + 1 {
      let (name, _) = ownership[i]
      if name == ref_type {
        is_defined = true
        break
      }
    }
    if not(is_defined) &&
      not(array_contains(builtins, ref_type)) &&
      not(array_contains(undefined, ref_type)) &&
      not(is_lowercase) {
      undefined.push(ref_type)
    }
  }
  undefined
}

///|
/// 未定義の外部型を抽出
fn collect_undefined_external_types(
  definitions : Array[Definition],
) -> Array[String] {
  let defined = collect_defined_types(definitions)
  let referenced = collect_referenced_types(definitions)
  let undefined : Array[String] = []

  // 組み込み型は除外
  let builtins = [
    "JsValue", "Int", "Int64", "Double", "Bool", "String", "Unit", "Bytes",
  ]

  // ヘッダーで既に宣言される型も除外
  let header_types = [
    "HTMLCanvasElement", "HTMLImageElement", "HTMLVideoElement", "Element", "SVGImageElement",
    "SVGMatrix", "ImageBitmap", "ImageData", "OffscreenCanvas", "VideoFrame", "CanvasImageSource",
    "CanvasGradient", "CanvasPattern", "Path2D", "DOMMatrix", "DOMMatrix2DInit",
    "Uint8ClampedArray", "Float64Array",
  ]
  for ref_type in referenced {
    // 小文字始まりは除外 (object など無効な型名)
    let first_char = get_first_char(ref_type)
    let is_lowercase = first_char >= 'a' && first_char <= 'z'
    if not(array_contains(defined, ref_type)) &&
      not(array_contains(builtins, ref_type)) &&
      not(array_contains(header_types, ref_type)) &&
      not(array_contains(undefined, ref_type)) &&
      not(is_lowercase) {
      undefined.push(ref_type)
    }
  }
  undefined
}

///|
/// 文字列の最初の文字を取得
fn get_first_char(s : String) -> Char {
  for c in s {
    return c
  }
  ' '
}

///|
/// 型名が除外リストに含まれるかチェック
fn is_excluded_type(name : String, exclude : Array[String]) -> Bool {
  for t in exclude {
    if t == name {
      return true
    }
  }
  false
}

///|
/// 外部型を出力（除外リストにない場合のみ）
fn write_external_type(
  result : StringBuilder,
  name : String,
  exclude : Array[String],
  comment : String,
) -> Unit {
  if not(is_excluded_type(name, exclude)) {
    result.write_string("pub type ")
    result.write_string(name)
    if comment != "" {
      result.write_string("  ")
      result.write_string(comment)
    }
    result.write_string("\n")
  }
}

///|
/// ファイルヘッダーを生成（除外する型を指定可能）
pub fn gen_file_header_with_exclude(
  source_file : String,
  exclude : Array[String],
) -> String {
  let result = StringBuilder::new()
  result.write_string("// Generated from WebIDL - DO NOT EDIT\n")
  result.write_string("// Source: ")
  result.write_string(source_file)
  result.write_string("\n")
  result.write_string("//\n")
  result.write_string("// Re-generate with: webidl-bindgen --input ")
  result.write_string(source_file)
  result.write_string("\n\n")

  // Add common external type definitions (excluding types defined in WebIDL)
  result.write_string("// External types\n")
  write_external_type(result, "JsValue", exclude, "")
  result.write_string("\n")

  // JsValue helper functions
  result.write_string(
    "pub extern \"js\" fn JsValue::undefined() -> JsValue =\n",
  )
  result.write_string("  #| () => undefined\n\n")
  result.write_string("// HTML Elements\n")
  write_external_type(result, "HTMLCanvasElement", exclude, "")
  write_external_type(result, "HTMLImageElement", exclude, "")
  write_external_type(result, "HTMLVideoElement", exclude, "")
  write_external_type(result, "Element", exclude, "")
  result.write_string("\n")
  result.write_string("// SVG Elements\n")
  write_external_type(result, "SVGImageElement", exclude, "")
  write_external_type(result, "SVGMatrix", exclude, "")
  result.write_string("\n")
  result.write_string("// Canvas/Image types\n")
  write_external_type(result, "ImageBitmap", exclude, "")
  write_external_type(result, "ImageData", exclude, "")
  write_external_type(result, "OffscreenCanvas", exclude, "")
  write_external_type(result, "VideoFrame", exclude, "")
  write_external_type(result, "CanvasImageSource", exclude, "// union type")
  write_external_type(result, "CanvasGradient", exclude, "")
  write_external_type(result, "CanvasPattern", exclude, "")
  write_external_type(result, "Path2D", exclude, "")
  result.write_string("\n")
  result.write_string("// Matrix/Transform types\n")
  write_external_type(result, "DOMMatrix", exclude, "")
  write_external_type(result, "DOMMatrix2DInit", exclude, "")
  result.write_string("\n")
  result.write_string("// TypedArrays\n")
  write_external_type(result, "Uint8ClampedArray", exclude, "")
  write_external_type(result, "Float64Array", exclude, "")
  result.write_string("\n")
  result.to_string()
}

///|
/// ファイルヘッダーを生成（後方互換性用）
pub fn gen_file_header(source_file : String) -> String {
  gen_file_header_with_exclude(source_file, [])
}

///|
/// セクション区切りコメントを生成
pub fn gen_section_comment(title : String) -> String {
  let result = StringBuilder::new()
  result.write_string("// ")
  // タイトル幅に合わせて区切り線を作成
  let line_len = 60
  let mut title_len = 0
  for _ in title {
    title_len = title_len + 1
  }
  let padding = (line_len - title_len - 4) / 2
  let mut i = 0
  while i < padding {
    result.write_char('-')
    i = i + 1
  }
  result.write_string(" ")
  result.write_string(title)
  result.write_string(" ")
  i = 0
  while i < padding {
    result.write_char('-')
    i = i + 1
  }
  result.write_string("\n\n")
  result.to_string()
}

///|
/// 複数の定義をまとめてフォーマット
pub fn format_definitions(
  source_file : String,
  definitions : Array[Definition],
) -> String {
  let result = StringBuilder::new()

  // WebIDL で定義される型名を収集（重複定義を避けるため）
  let defined_types = collect_defined_types(definitions)

  // ファイルヘッダー（WebIDL で定義される型は除外）
  result.write_string(gen_file_header_with_exclude(source_file, defined_types))

  // 未定義の外部型を宣言
  let undefined_types = collect_undefined_external_types(definitions)
  if undefined_types.length() > 0 {
    result.write_string(
      "// Referenced external types (not defined in this WebIDL)\n",
    )
    for type_name in undefined_types {
      result.write_string("pub type ")
      result.write_string(type_name)
      result.write_string("\n")
    }
    result.write_string("\n")
  }

  // enum マップを作成（enum 引数の文字列変換に使用）
  let enum_map : Array[(String, Array[String])] = []
  for def in definitions {
    match def {
      Enum(e) => enum_map.push((e.name, e.values))
      _ => ()
    }
  }

  // Types セクション (enum, dictionary, typedef, callback interface)
  let mut has_types = false
  for def in definitions {
    match def {
      Enum(_) | Dictionary(_) | Typedef(_) | CallbackInterface(_) => {
        has_types = true
        break
      }
      _ => ()
    }
  }
  if has_types {
    result.write_string(gen_section_comment("Types"))

    // Typedef を先に出力（他の型から参照される可能性があるため）
    for def in definitions {
      match def {
        Typedef(t) => {
          result.write_string(gen_typedef(t))
          result.write_string("\n")
        }
        _ => ()
      }
    }

    // Enum を出力
    for def in definitions {
      match def {
        Enum(e) => {
          result.write_string(gen_enum(e))
          result.write_string("\n")
        }
        _ => ()
      }
    }

    // CallbackInterface を出力（opaque型 + from_fn ヘルパー）
    for def in definitions {
      match def {
        CallbackInterface(cb) => {
          result.write_string("/// ")
          result.write_string(cb.name)
          result.write_string(" callback interface\n")
          result.write_string("pub type ")
          result.write_string(cb.name)
          result.write_string("\n\n")
          // from_fn ヘルパーを生成（引数がある場合のみ）
          if cb.arguments.length() > 0 {
            result.write_string(gen_callback_from_fn(cb))
          }
        }
        _ => ()
      }
    }

    // Dictionary を出力
    for def in definitions {
      match def {
        Dictionary(d) => {
          result.write_string(gen_dictionary(d))
          result.write_string("\n")
        }
        _ => ()
      }
    }
  }

  // Interfaces セクション
  let mut has_interfaces = false
  for def in definitions {
    match def {
      Interface(_) => {
        has_interfaces = true
        break
      }
      _ => ()
    }
  }
  if has_interfaces {
    result.write_string(gen_section_comment("Interfaces"))
    for def in definitions {
      match def {
        Interface(iface) => {
          result.write_string(gen_interface_binding(iface, enum_map))
          result.write_string("\n")
        }
        _ => ()
      }
    }
  }
  result.to_string()
}

///|
/// 単一インターフェースをフォーマット（ヘッダー付き）
/// 注意: enum マップがないため、enum 引数の文字列変換は行われません
pub fn format_interface(source_file : String, iface : InterfaceDef) -> String {
  let result = StringBuilder::new()
  result.write_string(gen_file_header(source_file))
  let empty_enum_map : Array[(String, Array[String])] = []
  result.write_string(gen_interface_binding(iface, empty_enum_map))
  result.to_string()
}

///|
/// 連続する空行を1つにまとめる
pub fn normalize_blank_lines(code : String) -> String {
  let result = StringBuilder::new()
  let mut prev_was_blank = false
  let mut current_line = StringBuilder::new()
  for c in code {
    if c == '\n' {
      let line = current_line.to_string()
      let is_blank = is_blank_line(line)
      if is_blank {
        if not(prev_was_blank) {
          result.write_char('\n')
        }
        prev_was_blank = true
      } else {
        result.write_string(line)
        result.write_char('\n')
        prev_was_blank = false
      }
      current_line = StringBuilder::new()
    } else {
      current_line.write_char(c)
    }
  }

  // 最後の行を処理
  let last_line = current_line.to_string()
  if not(is_blank_line(last_line)) {
    result.write_string(last_line)
  }
  result.to_string()
}

///|
/// 空白行かどうか判定
fn is_blank_line(line : String) -> Bool {
  for c in line {
    if c != ' ' && c != '\t' {
      return false
    }
  }
  true
}

///|
/// インデントを正規化（タブをスペース2つに変換）
pub fn normalize_indent(code : String) -> String {
  let result = StringBuilder::new()
  for c in code {
    if c == '\t' {
      result.write_string("  ")
    } else {
      result.write_char(c)
    }
  }
  result.to_string()
}

///|
/// 全フォーマット処理を適用
pub fn format_output(
  source_file : String,
  definitions : Array[Definition],
) -> String {
  // First merge partial definitions into their targets
  let merged = merge_definitions(definitions)
  let code = format_definitions(source_file, merged)
  let code = normalize_indent(code)
  let code = normalize_blank_lines(code)
  code
}

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
  let mut best_ctor : ConstructorDef? = None
  let mut best_ctor_arg_count = -1
  let seen_ops : Array[(String, Int)] = []  // (name, arg_count)

  // Process existing members - track constructors and operations
  for mem in existing {
    match mem {
      Constructor(ctor) => {
        let arg_count = ctor.arguments.length()
        if arg_count > best_ctor_arg_count {
          best_ctor = Some(ctor)
          best_ctor_arg_count = arg_count
        }
      }
      Operation(op) => {
        seen_ops.push((op.name, op.arguments.length()))
        result.push(mem)
      }
      _ => result.push(mem)
    }
  }

  // Process new members
  for new_mem in new_members {
    match new_mem {
      Constructor(ctor) => {
        let arg_count = ctor.arguments.length()
        if arg_count > best_ctor_arg_count {
          best_ctor = Some(ctor)
          best_ctor_arg_count = arg_count
        }
      }
      Operation(op) => {
        // Check if this (name, arg_count) combination already exists
        let mut is_duplicate = false
        for entry in seen_ops {
          if entry.0 == op.name && entry.1 == op.arguments.length() {
            is_duplicate = true
            break
          }
        }
        if not(is_duplicate) {
          // Also skip if same name but different arg count (method overloading not supported)
          let mut name_exists = false
          for entry in seen_ops {
            if entry.0 == op.name && op.name != "" {
              name_exists = true
              break
            }
          }
          if not(name_exists) {
            seen_ops.push((op.name, op.arguments.length()))
            result.push(new_mem)
          }
        }
      }
      _ => {
        let new_name = get_member_name(new_mem)
        let mut is_duplicate = false
        for existing_mem in existing {
          if get_member_name(existing_mem) == new_name && new_name != "" {
            is_duplicate = true
            break
          }
        }
        if not(is_duplicate) {
          result.push(new_mem)
        }
      }
    }
  }

  // Add the best constructor at the end
  match best_ctor {
    Some(ctor) => result.push(Constructor(ctor))
    None => ()
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
/// 共通型定義を生成（per-spec モード用）
pub fn gen_shared_types_with_externals(
  external_types : Array[String],
) -> String {
  let result = StringBuilder::new()
  result.write_string("// Shared types for websys\n")
  result.write_string("// Generated by webidl-bindgen\n\n")

  // JsValue type
  result.write_string("/// Generic JavaScript value\n")
  result.write_string("pub type JsValue\n\n")

  // undefined helper
  result.write_string("/// Return undefined\n")
  result.write_string(
    "pub extern \"js\" fn JsValue::undefined() -> JsValue =\n",
  )
  result.write_string("  #| () => undefined\n\n")

  // null helper
  result.write_string("/// Return null\n")
  result.write_string("pub extern \"js\" fn JsValue::null() -> JsValue =\n")
  result.write_string("  #| () => null\n\n")

  // from_string helper
  result.write_string("/// Create JsValue from String\n")
  result.write_string(
    "pub extern \"js\" fn JsValue::from_string(s : String) -> JsValue =\n",
  )
  result.write_string("  #| (s) => s\n\n")

  // from_int helper
  result.write_string("/// Create JsValue from Int\n")
  result.write_string(
    "pub extern \"js\" fn JsValue::from_int(i : Int) -> JsValue =\n",
  )
  result.write_string("  #| (i) => i\n\n")

  // from_double helper
  result.write_string("/// Create JsValue from Double\n")
  result.write_string(
    "pub extern \"js\" fn JsValue::from_double(d : Double) -> JsValue =\n",
  )
  result.write_string("  #| (d) => d\n\n")

  // from_bool helper
  result.write_string("/// Create JsValue from Bool\n")
  result.write_string(
    "pub extern \"js\" fn JsValue::from_bool(b : Bool) -> JsValue =\n",
  )
  result.write_string("  #| (b) => b\n\n")

  // Promise type (WebIDL built-in)
  result.write_string("/// JavaScript Promise type\n")
  result.write_string("pub type Promise[T]\n\n")

  // External type declarations
  if external_types.length() > 0 {
    result.write_string(
      "// External types (referenced but not defined in WebIDL specs)\n",
    )
    for ext_type in external_types {
      result.write_string("pub type ")
      result.write_string(ext_type)
      result.write_string("\n")
    }
    result.write_string("\n")
  }
  result.to_string()
}

///|
/// 仕様ごとのフォーマット出力（外部型宣言なし）
pub fn format_spec_output(
  spec_name : String,
  definitions : Array[Definition],
  global_enum_map : Array[(String, Array[String])],
) -> String {
  let result = StringBuilder::new()

  // Header
  result.write_string("// Generated from WebIDL - DO NOT EDIT\n")
  result.write_string("// Source: @webref/idl/")
  result.write_string(spec_name)
  result.write_string("\n\n")

  // Types セクション (typedef, enum, callback interface, dictionary)
  let mut has_types = false
  for def in definitions {
    match def {
      Typedef(_) | Enum(_) | Dictionary(_) | CallbackInterface(_) => {
        has_types = true
        break
      }
      _ => ()
    }
  }
  if has_types {
    // Typedef を先に出力
    for def in definitions {
      match def {
        Typedef(t) => {
          result.write_string(gen_typedef(t))
          result.write_string("\n")
        }
        _ => ()
      }
    }

    // Enum を出力
    for def in definitions {
      match def {
        Enum(e) => {
          result.write_string(gen_enum(e))
          result.write_string("\n")
        }
        _ => ()
      }
    }

    // CallbackInterface を出力（opaque型 + from_fn ヘルパー）
    for def in definitions {
      match def {
        CallbackInterface(cb) => {
          result.write_string("/// ")
          result.write_string(cb.name)
          result.write_string(" callback interface\n")
          result.write_string("pub type ")
          result.write_string(cb.name)
          result.write_string("\n\n")
          // from_fn ヘルパーを生成（引数がある場合のみ）
          if cb.arguments.length() > 0 {
            result.write_string(gen_callback_from_fn(cb))
          }
        }
        _ => ()
      }
    }

    // Dictionary を出力
    for def in definitions {
      match def {
        Dictionary(d) => {
          result.write_string(gen_dictionary(d))
          result.write_string("\n")
        }
        _ => ()
      }
    }
  }

  // Interfaces セクション
  for def in definitions {
    match def {
      Interface(iface) => {
        result.write_string(gen_interface_binding(iface, global_enum_map))
        result.write_string("\n")
      }
      _ => ()
    }
  }
  let code = result.to_string()
  let code = normalize_indent(code)
  let code = normalize_blank_lines(code)
  code
}

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
           parent_name, visited,
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
            interfaces, grandparent_name, new_visited,
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
           parent_name, visited,
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
            dictionaries, grandparent_name, new_visited,
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

///|
/// Callback interface の from_fn ヘルパーを生成
/// 例: pub extern "js" fn EventListener::from_fn(handler : (Event) -> Unit) -> EventListener
fn gen_callback_from_fn(cb : CallbackInterfaceDef) -> String {
  let result = StringBuilder::new()

  // ドキュメントコメント
  result.write_string("/// Create ")
  result.write_string(cb.name)
  result.write_string(" from a MoonBit function\n")

  // 関数シグネチャ
  result.write_string("pub extern \"js\" fn ")
  result.write_string(cb.name)
  result.write_string("::from_fn(handler : (")

  // 引数の型リスト
  let args_len = cb.arguments.length()
  for i = 0; i < args_len; i = i + 1 {
    let arg = cb.arguments[i]
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string(idl_type_to_moonbit(arg.idl_type))
  }

  // 戻り値の型
  result.write_string(") -> ")
  match cb.return_type {
    Some(Void) | None => result.write_string("Unit")
    Some(t) => result.write_string(idl_type_to_moonbit(t))
  }

  // 関数の戻り値（Callback型）
  result.write_string(") -> ")
  result.write_string(cb.name)
  result.write_string(" =\n")

  // JS実装（MoonBit関数はそのままJS関数として使える）
  result.write_string("  #| (handler) => handler\n\n")
  result.to_string()
}

// ==== Sub-packages mode functions ====

///|
/// 各 spec が参照する型を収集し、複数 spec から参照される型を特定
pub fn find_cross_spec_referenced_types(
  results : Array[SpecLoadResult],
  ownership : Array[(String, String)],
) -> Array[String] {
  // spec_name -> [referenced_type_names]
  let spec_refs : Array[(String, Array[String])] = []
  for result in results {
    if result.success {
      let refs = collect_referenced_types(result.definitions)
      spec_refs.push((result.spec_name, refs))
    }
  }

  // Count how many specs reference each type
  let type_counts : Array[(String, Int)] = []
  for i = 0; i < ownership.length(); i = i + 1 {
    let (type_name, _owner) = ownership[i]
    let mut count = 0
    for j = 0; j < spec_refs.length(); j = j + 1 {
      let (_spec, refs) = spec_refs[j]
      for ref_type in refs {
        if ref_type == type_name {
          count = count + 1
          break
        }
      }
    }
    if count > 1 {
      type_counts.push((type_name, count))
    }
  }

  // Return types referenced by multiple specs
  let cross_spec_types : Array[String] = []
  for i = 0; i < type_counts.length(); i = i + 1 {
    let (type_name, _) = type_counts[i]
    cross_spec_types.push(type_name)
  }
  cross_spec_types
}

///|
/// サブパッケージ用の moon.pkg.json を生成
pub fn gen_moon_pkg_json(module_name : String) -> String {
  let result = StringBuilder::new()
  result.write_string("{\n")
  result.write_string("  \"import\": [\n")
  result.write_string("    \"")
  result.write_string(module_name)
  result.write_string("\"\n")
  result.write_string("  ],\n")
  result.write_string("  \"supported-targets\": [\"js\"]\n")
  result.write_string("}\n")
  result.to_string()
}

///|
/// 型参照を @parent.Type 形式に変換
fn convert_type_reference(
  type_name : String,
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  // Check if this type is in parent package
  for pt in parent_types {
    if pt == type_name {
      return parent_alias + "." + type_name
    }
  }
  type_name
}

///|
/// サブパッケージ用のコードを生成（型参照を @parent.Type に変換）
pub fn format_sub_package_output(
  spec_name : String,
  definitions : Array[Definition],
  global_enum_map : Array[(String, Array[String])],
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  let result = StringBuilder::new()

  // Header
  result.write_string("// Generated from WebIDL - DO NOT EDIT\n")
  result.write_string("// Source: @webref/idl/")
  result.write_string(spec_name)
  result.write_string("\n")
  result.write_string("// Sub-package mode: references to shared types use ")
  result.write_string(parent_alias)
  result.write_string(". prefix\n\n")

  // Generate code with converted type references
  // For now, use the same generation but with type conversion
  // TODO: Implement proper type reference conversion in gen_* functions

  // Types section
  let mut has_types = false
  for def in definitions {
    match def {
      Typedef(_) | Enum(_) | Dictionary(_) | CallbackInterface(_) => {
        has_types = true
        break
      }
      _ => ()
    }
  }
  if has_types {
    for def in definitions {
      match def {
        Typedef(t) => {
          result.write_string(gen_typedef_with_conversion(t, parent_types, parent_alias))
          result.write_string("\n")
        }
        _ => ()
      }
    }
    for def in definitions {
      match def {
        Enum(e) => {
          result.write_string(gen_enum(e))
          result.write_string("\n")
        }
        _ => ()
      }
    }
    for def in definitions {
      match def {
        CallbackInterface(cb) => {
          result.write_string("/// ")
          result.write_string(cb.name)
          result.write_string(" callback interface\n")
          result.write_string("pub type ")
          result.write_string(cb.name)
          result.write_string("\n\n")
          if cb.arguments.length() > 0 {
            result.write_string(gen_callback_from_fn_with_conversion(cb, parent_types, parent_alias))
          }
        }
        _ => ()
      }
    }
    for def in definitions {
      match def {
        Dictionary(d) => {
          result.write_string(gen_dictionary_with_conversion(d, parent_types, parent_alias))
          result.write_string("\n")
        }
        _ => ()
      }
    }
  }

  // Interfaces
  for def in definitions {
    match def {
      Interface(iface) => {
        result.write_string(gen_interface_with_conversion(iface, global_enum_map, parent_types, parent_alias))
        result.write_string("\n")
      }
      _ => ()
    }
  }

  result.to_string()
}

///|
/// Typedef 生成（型参照変換付き）
fn gen_typedef_with_conversion(
  t : TypedefDef,
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  let result = StringBuilder::new()
  result.write_string("///|\n")
  result.write_string("/// ")
  result.write_string(t.name)
  result.write_string(" typedef\n")
  result.write_string("pub type ")
  result.write_string(t.name)
  result.write_string(" = ")
  result.write_string(idl_type_to_moonbit_with_conversion(t.idl_type, parent_types, parent_alias))
  result.write_string("\n")
  result.to_string()
}

///|
/// Dictionary 生成（型参照変換付き）
fn gen_dictionary_with_conversion(
  d : DictionaryDef,
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  let result = StringBuilder::new()
  result.write_string("/// ")
  result.write_string(d.name)
  result.write_string(" dictionary\n")
  result.write_string("pub(all) struct ")
  result.write_string(d.name)
  result.write_string(" {\n")
  for mem in d.members {
    result.write_string("  ")
    result.write_string(escape_reserved(to_snake_case(mem.name)))
    result.write_string(" : ")
    let moonbit_type = idl_type_to_moonbit_with_conversion(mem.idl_type, parent_types, parent_alias)
    if mem.required {
      result.write_string(moonbit_type)
    } else {
      result.write_string(moonbit_type)
      result.write_string("?")
    }
    result.write_string("\n")
  }
  result.write_string("}\n\n")
  // to_js helper
  result.write_string("pub extern \"js\" fn ")
  result.write_string(d.name)
  result.write_string("::to_js(self : ")
  result.write_string(d.name)
  result.write_string(") -> ")
  result.write_string(convert_type_reference("JsValue", parent_types, parent_alias))
  result.write_string(" =\n")
  result.write_string("  #| (self) => self\n")
  result.to_string()
}

///|
/// Callback interface from_fn 生成（型参照変換付き）
fn gen_callback_from_fn_with_conversion(
  cb : CallbackInterfaceDef,
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  let result = StringBuilder::new()
  result.write_string("/// Create ")
  result.write_string(cb.name)
  result.write_string(" from a MoonBit function\n")
  result.write_string("pub extern \"js\" fn ")
  result.write_string(cb.name)
  result.write_string("::from_fn(handler : (")
  let mut first = true
  for arg in cb.arguments {
    if not(first) {
      result.write_string(", ")
    }
    first = false
    result.write_string(idl_type_to_moonbit_with_conversion(arg.idl_type, parent_types, parent_alias))
  }
  result.write_string(") -> ")
  result.write_string(convert_type_reference("JsValue", parent_types, parent_alias))
  result.write_string(") -> ")
  result.write_string(cb.name)
  result.write_string(" =\n")
  result.write_string("  #| (handler) => handler\n\n")
  result.to_string()
}

///|
/// Interface 生成（型参照変換付き）
fn gen_interface_with_conversion(
  iface : InterfaceDef,
  global_enum_map : Array[(String, Array[String])],
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  let result = StringBuilder::new()

  // Type declaration
  result.write_string("/// ")
  result.write_string(iface.name)
  result.write_string(" interface\n")
  result.write_string("pub type ")
  result.write_string(iface.name)
  result.write_string("\n\n")

  // to_js_value helper
  result.write_string("pub extern \"js\" fn ")
  result.write_string(iface.name)
  result.write_string("::to_js_value(self : ")
  result.write_string(iface.name)
  result.write_string(") -> ")
  result.write_string(convert_type_reference("JsValue", parent_types, parent_alias))
  result.write_string(" =\n")
  result.write_string("  #| (self) => self\n\n")

  // Members
  for mem in iface.members {
    result.write_string(gen_member_with_conversion(mem, iface.name, global_enum_map, parent_types, parent_alias))
  }

  result.to_string()
}

///|
/// Member 生成（型参照変換付き）
fn gen_member_with_conversion(
  mem : InterfaceMember,
  iface_name : String,
  global_enum_map : Array[(String, Array[String])],
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  match mem {
    Attribute(attr) => gen_attribute_with_conversion(attr, iface_name, parent_types, parent_alias)
    Operation(op) => gen_operation_with_conversion(op, iface_name, global_enum_map, parent_types, parent_alias)
    Constructor(ctor) => gen_constructor_with_conversion(ctor, iface_name, global_enum_map, parent_types, parent_alias)
    Const(c) => gen_const_with_conversion(c, iface_name, parent_types, parent_alias)
    Maplike(_) => "" // Maplike not supported in sub-package mode yet
    Setlike(_) => "" // Setlike not supported in sub-package mode yet
  }
}

///|
fn gen_attribute_with_conversion(
  attr : AttributeDef,
  iface_name : String,
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  let result = StringBuilder::new()
  let moonbit_type = idl_type_to_moonbit_with_conversion(attr.idl_type, parent_types, parent_alias)

  // Getter
  result.write_string("pub extern \"js\" fn ")
  result.write_string(iface_name)
  result.write_string("::get_")
  result.write_string(to_snake_case(attr.name))
  result.write_string("(self : ")
  result.write_string(iface_name)
  result.write_string(") -> ")
  result.write_string(moonbit_type)
  result.write_string(" =\n")
  result.write_string("  #| (self) => self.")
  result.write_string(attr.name)
  result.write_string("\n\n")

  // Setter (if not readonly)
  if not(attr.is_readonly) {
    result.write_string("pub extern \"js\" fn ")
    result.write_string(iface_name)
    result.write_string("::set_")
    result.write_string(to_snake_case(attr.name))
    result.write_string("(self : ")
    result.write_string(iface_name)
    result.write_string(", value : ")
    result.write_string(moonbit_type)
    result.write_string(") -> Unit =\n")
    result.write_string("  #| (self, value) => { self.")
    result.write_string(attr.name)
    result.write_string(" = value }\n\n")
  }

  result.to_string()
}

///|
fn gen_operation_with_conversion(
  op : OperationDef,
  iface_name : String,
  global_enum_map : Array[(String, Array[String])],
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  let result = StringBuilder::new()

  if op.name == "" {
    return ""
  }

  // Generate multiple overloads for optional args
  gen_operation_overloads_with_conversion(
    result, op, iface_name, global_enum_map, parent_types, parent_alias,
  )

  result.to_string()
}

///|
fn gen_operation_overloads_with_conversion(
  result : StringBuilder,
  op : OperationDef,
  iface_name : String,
  global_enum_map : Array[(String, Array[String])],
  parent_types : Array[String],
  parent_alias : String,
) -> Unit {
  let required_count = {
    let mut count = 0
    for arg in op.arguments {
      if not(arg.optional) {
        count = count + 1
      }
    }
    count
  }
  let total_count = op.arguments.length()

  // Generate overloads from required_count to total_count
  for arg_count = required_count; arg_count <= total_count; arg_count = arg_count + 1 {
    gen_single_operation_with_conversion(
      result, op, iface_name, arg_count, global_enum_map, parent_types, parent_alias,
    )
  }
}

///|
fn gen_single_operation_with_conversion(
  result : StringBuilder,
  op : OperationDef,
  iface_name : String,
  arg_count : Int,
  global_enum_map : Array[(String, Array[String])],
  parent_types : Array[String],
  parent_alias : String,
) -> Unit {
  let suffix = if arg_count < op.arguments.length() {
    "_" + arg_count.to_string()
  } else {
    ""
  }

  let return_type = idl_type_to_moonbit_with_conversion(op.return_type, parent_types, parent_alias)
  let is_static = match op.special {
    Some("static") => true
    _ => false
  }

  // Signature
  if is_static {
    result.write_string("pub extern \"js\" fn ")
    result.write_string(iface_name)
    result.write_string("::")
    result.write_string(to_snake_case(op.name))
    result.write_string(suffix)
    result.write_string("(")
  } else {
    result.write_string("pub extern \"js\" fn ")
    result.write_string(iface_name)
    result.write_string("::")
    result.write_string(to_snake_case(op.name))
    result.write_string(suffix)
    result.write_string("(self : ")
    result.write_string(iface_name)
  }

  // Arguments
  for i = 0; i < arg_count; i = i + 1 {
    let arg = op.arguments[i]
    if i > 0 || not(is_static) {
      result.write_string(", ")
    }
    result.write_string(escape_reserved(to_snake_case(arg.name)))
    result.write_string(" : ")
    result.write_string(idl_type_to_moonbit_with_conversion(arg.idl_type, parent_types, parent_alias))
  }

  result.write_string(") -> ")
  result.write_string(return_type)
  result.write_string(" =\n")

  // JS implementation
  result.write_string("  #| ")
  if is_static {
    result.write_string("(")
    for i = 0; i < arg_count; i = i + 1 {
      if i > 0 {
        result.write_string(", ")
      }
      result.write_string(escape_reserved(to_snake_case(op.arguments[i].name)))
    }
    result.write_string(") => ")
    result.write_string(iface_name)
    result.write_string(".")
    result.write_string(op.name)
    result.write_string("(")
    for i = 0; i < arg_count; i = i + 1 {
      if i > 0 {
        result.write_string(", ")
      }
      result.write_string(escape_reserved(to_snake_case(op.arguments[i].name)))
    }
    result.write_string(")\n\n")
  } else {
    result.write_string("(self")
    for i = 0; i < arg_count; i = i + 1 {
      result.write_string(", ")
      result.write_string(escape_reserved(to_snake_case(op.arguments[i].name)))
    }
    result.write_string(") => self.")
    result.write_string(op.name)
    result.write_string("(")
    for i = 0; i < arg_count; i = i + 1 {
      if i > 0 {
        result.write_string(", ")
      }
      result.write_string(escape_reserved(to_snake_case(op.arguments[i].name)))
    }
    result.write_string(")\n\n")
  }
}

///|
fn gen_constructor_with_conversion(
  ctor : ConstructorDef,
  iface_name : String,
  global_enum_map : Array[(String, Array[String])],
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  let result = StringBuilder::new()

  let required_count = {
    let mut count = 0
    for arg in ctor.arguments {
      if not(arg.optional) {
        count = count + 1
      }
    }
    count
  }
  let total_count = ctor.arguments.length()

  for arg_count = required_count; arg_count <= total_count; arg_count = arg_count + 1 {
    let suffix = if arg_count < total_count {
      "_" + arg_count.to_string()
    } else {
      ""
    }

    result.write_string("pub extern \"js\" fn ")
    result.write_string(iface_name)
    result.write_string("::new")
    result.write_string(suffix)
    result.write_string("(")

    for i = 0; i < arg_count; i = i + 1 {
      if i > 0 {
        result.write_string(", ")
      }
      let arg = ctor.arguments[i]
      result.write_string(escape_reserved(to_snake_case(arg.name)))
      result.write_string(" : ")
      result.write_string(idl_type_to_moonbit_with_conversion(arg.idl_type, parent_types, parent_alias))
    }

    result.write_string(") -> ")
    result.write_string(iface_name)
    result.write_string(" =\n")
    result.write_string("  #| (")
    for i = 0; i < arg_count; i = i + 1 {
      if i > 0 {
        result.write_string(", ")
      }
      result.write_string(escape_reserved(to_snake_case(ctor.arguments[i].name)))
    }
    result.write_string(") => new ")
    result.write_string(iface_name)
    result.write_string("(")
    for i = 0; i < arg_count; i = i + 1 {
      if i > 0 {
        result.write_string(", ")
      }
      result.write_string(escape_reserved(to_snake_case(ctor.arguments[i].name)))
    }
    result.write_string(")\n\n")
  }

  result.to_string()
}

///|
fn gen_const_with_conversion(
  c : ConstDef,
  iface_name : String,
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  let result = StringBuilder::new()
  let moonbit_type = idl_type_to_moonbit_with_conversion(c.idl_type, parent_types, parent_alias)

  result.write_string("pub extern \"js\" fn ")
  result.write_string(iface_name)
  result.write_string("::get_")
  result.write_string(to_snake_case(c.name))
  result.write_string("() -> ")
  result.write_string(moonbit_type)
  result.write_string(" =\n")
  result.write_string("  #| () => ")
  result.write_string(iface_name)
  result.write_string(".")
  result.write_string(c.name)
  result.write_string("\n\n")

  result.to_string()
}

///|
/// IDL 型を MoonBit 型に変換（親パッケージ型参照付き）
fn idl_type_to_moonbit_with_conversion(
  idl_type : IdlType,
  parent_types : Array[String],
  parent_alias : String,
) -> String {
  match idl_type {
    Primitive(name) =>
      match name {
        "boolean" => "Bool"
        "byte" | "octet" | "short" | "unsigned short" | "long" | "unsigned long" => "Int"
        "long long" | "unsigned long long" => "Int64"
        "float" | "unrestricted float" | "double" | "unrestricted double" => "Double"
        _ => convert_type_reference("JsValue", parent_types, parent_alias)
      }
    String => "String"
    Void => "Unit"
    Nullable(inner) => {
      let inner_type = idl_type_to_moonbit_with_conversion(inner, parent_types, parent_alias)
      if str_ends_with_question_char(inner_type) {
        inner_type
      } else {
        inner_type + "?"
      }
    }
    Named(name) => {
      let first_char = get_str_first_char_local(name)
      if first_char >= 'a' && first_char <= 'z' {
        convert_type_reference("JsValue", parent_types, parent_alias)
      } else {
        convert_type_reference(name, parent_types, parent_alias)
      }
    }
    Sequence(inner) => {
      let inner_type = idl_type_to_moonbit_with_conversion(inner, parent_types, parent_alias)
      "Array[" + inner_type + "]"
    }
    Promise(inner) => {
      let inner_type = idl_type_to_moonbit_with_conversion(inner, parent_types, parent_alias)
      convert_type_reference("Promise", parent_types, parent_alias) + "[" + inner_type + "]"
    }
    Union(_) => convert_type_reference("JsValue", parent_types, parent_alias)
    Any => convert_type_reference("JsValue", parent_types, parent_alias)
  }
}

///|
fn str_ends_with_question_char(s : String) -> Bool {
  let mut last_char = ' '
  for c in s {
    last_char = c
  }
  last_char == '?'
}

///|
fn get_str_first_char_local(s : String) -> Char {
  for c in s {
    return c
  }
  ' '
}

///|
/// サブパッケージ用の shared.mbt を生成（共有型を含む）
pub fn gen_sub_package_shared_types(
  external_types : Array[String],
  cross_spec_types : Array[String],
  all_definitions : Array[Definition],
) -> String {
  let result = StringBuilder::new()
  result.write_string("// Shared types for websys (sub-packages mode)\n")
  result.write_string("// Generated by webidl-bindgen\n\n")

  // JsValue type
  result.write_string("/// Generic JavaScript value\n")
  result.write_string("pub type JsValue\n\n")

  // undefined helper
  result.write_string("/// Return undefined\n")
  result.write_string("pub extern \"js\" fn JsValue::undefined() -> JsValue =\n")
  result.write_string("  #| () => undefined\n\n")

  // null helper
  result.write_string("/// Return null\n")
  result.write_string("pub extern \"js\" fn JsValue::null() -> JsValue =\n")
  result.write_string("  #| () => null\n\n")

  // from_string helper
  result.write_string("/// Create JsValue from String\n")
  result.write_string("pub extern \"js\" fn JsValue::from_string(s : String) -> JsValue =\n")
  result.write_string("  #| (s) => s\n\n")

  // from_int helper
  result.write_string("/// Create JsValue from Int\n")
  result.write_string("pub extern \"js\" fn JsValue::from_int(i : Int) -> JsValue =\n")
  result.write_string("  #| (i) => i\n\n")

  // from_double helper
  result.write_string("/// Create JsValue from Double\n")
  result.write_string("pub extern \"js\" fn JsValue::from_double(d : Double) -> JsValue =\n")
  result.write_string("  #| (d) => d\n\n")

  // from_bool helper
  result.write_string("/// Create JsValue from Bool\n")
  result.write_string("pub extern \"js\" fn JsValue::from_bool(b : Bool) -> JsValue =\n")
  result.write_string("  #| (b) => b\n\n")

  // Promise type
  result.write_string("/// JavaScript Promise type\n")
  result.write_string("pub type Promise[T]\n\n")

  // External types
  if external_types.length() > 0 {
    result.write_string("// External types (referenced but not defined in WebIDL specs)\n")
    for ext_type in external_types {
      result.write_string("pub type ")
      result.write_string(ext_type)
      result.write_string("\n")
    }
    result.write_string("\n")
  }

  // Cross-spec types (types referenced by multiple specs)
  if cross_spec_types.length() > 0 {
    result.write_string("// Cross-spec types (referenced by multiple specs)\n")
    for type_name in cross_spec_types {
      // Find the definition for this type
      for def in all_definitions {
        let def_name = get_definition_name(def)
        if def_name == type_name {
          match def {
            Interface(iface) => {
              result.write_string("/// ")
              result.write_string(iface.name)
              result.write_string(" interface (shared)\n")
              result.write_string("pub type ")
              result.write_string(iface.name)
              result.write_string("\n\n")
            }
            Typedef(t) => {
              // For cross-spec typedefs, only generate opaque type (full definition would need dependencies)
              result.write_string("/// ")
              result.write_string(t.name)
              result.write_string(" typedef (shared, opaque)\n")
              result.write_string("pub type ")
              result.write_string(t.name)
              result.write_string("\n\n")
            }
            Enum(e) => {
              result.write_string(gen_enum(e))
              result.write_string("\n")
            }
            CallbackInterface(cb) => {
              result.write_string("/// ")
              result.write_string(cb.name)
              result.write_string(" callback interface (shared)\n")
              result.write_string("pub type ")
              result.write_string(cb.name)
              result.write_string("\n\n")
            }
            Dictionary(d) => {
              // For cross-spec dictionaries, only generate opaque type (full definition would need dependencies)
              result.write_string("/// ")
              result.write_string(d.name)
              result.write_string(" dictionary (shared, opaque)\n")
              result.write_string("pub type ")
              result.write_string(d.name)
              result.write_string("\n\n")
            }
            _ => ()
          }
          break
        }
      }
    }
  }

  result.to_string()
}

///|
/// Core shared types (JsValue, Promise, external types only)
pub fn gen_core_shared_types(external_types : Array[String]) -> String {
  let result = StringBuilder::new()
  result.write_string("// Core shared types for websys\n")
  result.write_string("// Generated by webidl-bindgen\n\n")

  // JsValue type
  result.write_string("/// Generic JavaScript value\n")
  result.write_string("pub type JsValue\n\n")

  // JsValue helpers
  result.write_string("/// Return undefined\n")
  result.write_string("pub extern \"js\" fn JsValue::undefined() -> JsValue =\n")
  result.write_string("  #| () => undefined\n\n")

  result.write_string("/// Return null\n")
  result.write_string("pub extern \"js\" fn JsValue::null() -> JsValue =\n")
  result.write_string("  #| () => null\n\n")

  result.write_string("/// Create JsValue from String\n")
  result.write_string("pub extern \"js\" fn JsValue::from_string(s : String) -> JsValue =\n")
  result.write_string("  #| (s) => s\n\n")

  result.write_string("/// Create JsValue from Int\n")
  result.write_string("pub extern \"js\" fn JsValue::from_int(i : Int) -> JsValue =\n")
  result.write_string("  #| (i) => i\n\n")

  result.write_string("/// Create JsValue from Double\n")
  result.write_string("pub extern \"js\" fn JsValue::from_double(d : Double) -> JsValue =\n")
  result.write_string("  #| (d) => d\n\n")

  result.write_string("/// Create JsValue from Bool\n")
  result.write_string("pub extern \"js\" fn JsValue::from_bool(b : Bool) -> JsValue =\n")
  result.write_string("  #| (b) => b\n\n")

  // Promise type
  result.write_string("/// JavaScript Promise type\n")
  result.write_string("pub type Promise[T]\n\n")

  // External types
  if external_types.length() > 0 {
    result.write_string("// External types (referenced but not defined in WebIDL specs)\n")
    for ext_type in external_types {
      result.write_string("pub type ")
      result.write_string(ext_type)
      result.write_string("\n")
    }
    result.write_string("\n")
  }

  result.to_string()
}

///|
/// Generate moon.pkg.json with imports
pub fn gen_moon_pkg_json_with_imports(imports : Array[String]) -> String {
  let result = StringBuilder::new()
  result.write_string("{\n")
  result.write_string("  \"import\": [\n")
  for i, imp in imports {
    result.write_string("    \"")
    result.write_string(imp)
    result.write_string("\"")
    if i < imports.length() - 1 {
      result.write_string(",")
    }
    result.write_string("\n")
  }
  result.write_string("  ],\n")
  result.write_string("  \"supported-targets\": [\"js\"]\n")
  result.write_string("}\n")
  result.to_string()
}

///|
/// Generate sub-package output with type alias mapping
pub fn format_sub_package_output_v2(
  group_name : String,
  specs : Array[String],
  definitions : Array[Definition],
  global_enum_map : Array[(String, Array[String])],
  type_aliases : Array[(String, String)],
) -> String {
  let result = StringBuilder::new()

  // Header
  result.write_string("// Generated from WebIDL - DO NOT EDIT\n")
  result.write_string("// Package: ")
  result.write_string(group_name)
  result.write_string("\n")
  if specs.length() > 1 {
    result.write_string("// Merged specs: ")
    for i, s in specs {
      if i > 0 {
        result.write_string(", ")
      }
      result.write_string(s)
    }
    result.write_string("\n")
  }
  result.write_string("\n")

  // Generate each definition
  for def in definitions {
    let code = gen_definition_with_aliases(def, global_enum_map, type_aliases)
    if code.length() > 0 {
      result.write_string(code)
      result.write_string("\n")
    }
  }

  result.to_string()
}

///|
/// Generate a definition with type alias conversion
fn gen_definition_with_aliases(
  def : Definition,
  global_enum_map : Array[(String, Array[String])],
  type_aliases : Array[(String, String)],
) -> String {
  match def {
    Interface(iface) => gen_interface_with_aliases(iface, global_enum_map, type_aliases)
    Dictionary(d) => gen_dictionary_with_aliases(d, type_aliases)
    Typedef(t) => gen_typedef_with_aliases(t, type_aliases)
    Enum(e) => gen_enum(e)
    CallbackInterface(cb) => gen_callback_with_aliases(cb, type_aliases)
    InterfaceMixin(_) => ""
    Partial(_) => ""
    Includes(_) => ""
  }
}

///|
/// Deduplicate interface members: keep best constructor (most args), first operation/attribute per name
fn deduplicate_interface_members(members : Array[InterfaceMember]) -> Array[InterfaceMember] {
  let result : Array[InterfaceMember] = []
  let mut best_ctor : ConstructorDef? = None
  let mut best_ctor_arg_count = -1
  let seen_op_names : Array[String] = []
  let seen_attr_names : Array[String] = []

  for mem in members {
    match mem {
      Constructor(ctor) => {
        let arg_count = ctor.arguments.length()
        if arg_count > best_ctor_arg_count {
          best_ctor = Some(ctor)
          best_ctor_arg_count = arg_count
        }
      }
      Operation(op) => {
        // Keep first operation with each name (use snake_case for comparison)
        let snake_name = to_snake_case(op.name)
        let mut name_seen = false
        for name in seen_op_names {
          if name == snake_name {
            name_seen = true
            break
          }
        }
        if not(name_seen) && op.name != "" {
          seen_op_names.push(snake_name)
          result.push(mem)
        }
        // Skip operations with empty names (stringifier)
      }
      Attribute(attr) => {
        // Keep first attribute with each name (use snake_case for comparison)
        let snake_name = to_snake_case(attr.name)
        let mut name_seen = false
        for name in seen_attr_names {
          if name == snake_name {
            name_seen = true
            break
          }
        }
        if not(name_seen) {
          seen_attr_names.push(snake_name)
          result.push(mem)
        }
      }
      _ => result.push(mem)
    }
  }

  // Add the best constructor at the beginning
  match best_ctor {
    Some(ctor) => {
      let new_result : Array[InterfaceMember] = [Constructor(ctor)]
      for m in result {
        new_result.push(m)
      }
      return new_result
    }
    None => ()
  }

  result
}

///|
fn gen_interface_with_aliases(
  iface : InterfaceDef,
  global_enum_map : Array[(String, Array[String])],
  type_aliases : Array[(String, String)],
) -> String {
  let result = StringBuilder::new()

  result.write_string("///|\n")
  result.write_string("/// ")
  result.write_string(iface.name)
  result.write_string(" interface\n")
  result.write_string("pub type ")
  result.write_string(iface.name)
  result.write_string("\n\n")

  result.write_string("pub extern \"js\" fn ")
  result.write_string(iface.name)
  result.write_string("::to_js_value(self : ")
  result.write_string(iface.name)
  result.write_string(") -> ")
  result.write_string(resolve_type_alias("JsValue", type_aliases))
  result.write_string(" =\n")
  result.write_string("  #| (self) => self\n\n")

  // Deduplicate members: keep best constructor, first operation per name
  let deduped = deduplicate_interface_members(iface.members)

  for mem in deduped {
    let mem_code = gen_member_with_aliases(mem, iface.name, global_enum_map, type_aliases)
    if mem_code.length() > 0 {
      result.write_string(mem_code)
    }
  }

  result.to_string()
}

///|
fn gen_member_with_aliases(
  mem : InterfaceMember,
  iface_name : String,
  global_enum_map : Array[(String, Array[String])],
  type_aliases : Array[(String, String)],
) -> String {
  match mem {
    Attribute(attr) => gen_attribute_with_aliases(attr, iface_name, type_aliases)
    Operation(op) => gen_operation_with_aliases(op, iface_name, global_enum_map, type_aliases)
    Constructor(ctor) => gen_constructor_with_aliases(ctor, iface_name, type_aliases)
    Const(c) => gen_const_with_aliases(c, iface_name, type_aliases)
    Maplike(_) => ""
    Setlike(_) => ""
  }
}

///|
fn gen_attribute_with_aliases(
  attr : AttributeDef,
  iface_name : String,
  type_aliases : Array[(String, String)],
) -> String {
  let result = StringBuilder::new()
  let moonbit_type = idl_type_to_moonbit_with_aliases(attr.idl_type, type_aliases)

  result.write_string("pub extern \"js\" fn ")
  result.write_string(iface_name)
  result.write_string("::get_")
  result.write_string(to_snake_case(attr.name))
  result.write_string("(self : ")
  result.write_string(iface_name)
  result.write_string(") -> ")
  result.write_string(moonbit_type)
  result.write_string(" =\n")
  result.write_string("  #| (self) => self.")
  result.write_string(attr.name)
  result.write_string("\n\n")

  if not(attr.is_readonly) {
    result.write_string("pub extern \"js\" fn ")
    result.write_string(iface_name)
    result.write_string("::set_")
    result.write_string(to_snake_case(attr.name))
    result.write_string("(self : ")
    result.write_string(iface_name)
    result.write_string(", value : ")
    result.write_string(moonbit_type)
    result.write_string(") -> Unit =\n")
    result.write_string("  #| (self, value) => { self.")
    result.write_string(attr.name)
    result.write_string(" = value }\n\n")
  }

  result.to_string()
}

///|
fn gen_operation_with_aliases(
  op : OperationDef,
  iface_name : String,
  global_enum_map : Array[(String, Array[String])],
  type_aliases : Array[(String, String)],
) -> String {
  // Skip operations with empty names (e.g., stringifier)
  if op.name == "" {
    return ""
  }

  let result = StringBuilder::new()

  let is_static = match op.special {
    Some("static") => true
    _ => false
  }

  let return_type = idl_type_to_moonbit_with_aliases(op.return_type, type_aliases)

  result.write_string("pub extern \"js\" fn ")
  result.write_string(iface_name)
  result.write_string("::")
  result.write_string(escape_reserved(to_snake_case(op.name)))
  result.write_string("(")

  if not(is_static) {
    result.write_string("self : ")
    result.write_string(iface_name)
    if op.arguments.length() > 0 {
      result.write_string(", ")
    }
  }

  for i, arg in op.arguments {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string(escape_reserved(to_snake_case(arg.name)))
    result.write_string(" : ")
    result.write_string(idl_type_to_moonbit_with_aliases(arg.idl_type, type_aliases))
  }

  result.write_string(") -> ")
  result.write_string(return_type)
  result.write_string(" =\n")

  result.write_string("  #| (")
  if not(is_static) {
    result.write_string("self")
    if op.arguments.length() > 0 {
      result.write_string(", ")
    }
  }
  for i, arg in op.arguments {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string(escape_reserved(to_snake_case(arg.name)))
  }
  result.write_string(") => ")

  if is_static {
    result.write_string(iface_name)
    result.write_string(".")
  } else {
    result.write_string("self.")
  }
  result.write_string(op.name)
  result.write_string("(")
  for i, arg in op.arguments {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string(escape_reserved(to_snake_case(arg.name)))
  }
  result.write_string(")\n\n")

  result.to_string()
}

///|
fn gen_constructor_with_aliases(
  ctor : ConstructorDef,
  iface_name : String,
  type_aliases : Array[(String, String)],
) -> String {
  let result = StringBuilder::new()

  result.write_string("pub extern \"js\" fn ")
  result.write_string(iface_name)
  result.write_string("::new(")

  for i, arg in ctor.arguments {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string(escape_reserved(to_snake_case(arg.name)))
    result.write_string(" : ")
    result.write_string(idl_type_to_moonbit_with_aliases(arg.idl_type, type_aliases))
  }

  result.write_string(") -> ")
  result.write_string(iface_name)
  result.write_string(" =\n")
  result.write_string("  #| (")

  for i, arg in ctor.arguments {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string(escape_reserved(to_snake_case(arg.name)))
  }

  result.write_string(") => new ")
  result.write_string(iface_name)
  result.write_string("(")

  for i, arg in ctor.arguments {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string(escape_reserved(to_snake_case(arg.name)))
  }

  result.write_string(")\n\n")

  result.to_string()
}

///|
fn gen_const_with_aliases(
  c : ConstDef,
  iface_name : String,
  type_aliases : Array[(String, String)],
) -> String {
  let result = StringBuilder::new()
  let moonbit_type = idl_type_to_moonbit_with_aliases(c.idl_type, type_aliases)

  result.write_string("pub extern \"js\" fn ")
  result.write_string(iface_name)
  result.write_string("::get_")
  result.write_string(to_snake_case(c.name))
  result.write_string("() -> ")
  result.write_string(moonbit_type)
  result.write_string(" =\n")
  result.write_string("  #| () => ")
  result.write_string(iface_name)
  result.write_string(".")
  result.write_string(c.name)
  result.write_string("\n\n")

  result.to_string()
}

///|
fn gen_dictionary_with_aliases(
  d : DictionaryDef,
  type_aliases : Array[(String, String)],
) -> String {
  let result = StringBuilder::new()

  result.write_string("///|\n")
  result.write_string("/// ")
  result.write_string(d.name)
  result.write_string(" dictionary\n")
  result.write_string("pub struct ")
  result.write_string(d.name)
  result.write_string(" {\n")

  for mem in d.members {
    result.write_string("  ")
    result.write_string(escape_reserved(to_snake_case(mem.name)))
    result.write_string(" : ")
    let mem_type = idl_type_to_moonbit_with_aliases(mem.idl_type, type_aliases)
    if mem.required {
      result.write_string(mem_type)
    } else {
      result.write_string(mem_type)
      result.write_string("?")
    }
    result.write_string("\n")
  }

  result.write_string("}\n\n")

  result.to_string()
}

///|
fn gen_typedef_with_aliases(
  t : TypedefDef,
  type_aliases : Array[(String, String)],
) -> String {
  let result = StringBuilder::new()

  result.write_string("///|\n")
  result.write_string("/// ")
  result.write_string(t.name)
  result.write_string(" typedef\n")
  result.write_string("pub type ")
  result.write_string(t.name)
  result.write_string(" = ")
  result.write_string(idl_type_to_moonbit_with_aliases(t.idl_type, type_aliases))
  result.write_string("\n\n")

  result.to_string()
}

///|
fn gen_callback_with_aliases(
  cb : CallbackInterfaceDef,
  type_aliases : Array[(String, String)],
) -> String {
  let result = StringBuilder::new()

  result.write_string("///|\n")
  result.write_string("/// ")
  result.write_string(cb.name)
  result.write_string(" callback\n")
  result.write_string("pub type ")
  result.write_string(cb.name)
  result.write_string("\n\n")

  result.to_string()
}

///|
fn idl_type_to_moonbit_with_aliases(
  idl_type : IdlType,
  type_aliases : Array[(String, String)],
) -> String {
  match idl_type {
    Primitive(name) =>
      match name {
        "boolean" => "Bool"
        "byte" | "octet" | "short" | "unsigned short" | "long" | "unsigned long" => "Int"
        "long long" | "unsigned long long" => "Int64"
        "float" | "unrestricted float" | "double" | "unrestricted double" => "Double"
        _ => resolve_type_alias("JsValue", type_aliases)
      }
    String => "String"
    Void => "Unit"
    Nullable(inner) => {
      let inner_type = idl_type_to_moonbit_with_aliases(inner, type_aliases)
      if ends_with_question_v2(inner_type) {
        inner_type
      } else {
        inner_type + "?"
      }
    }
    Named(name) => {
      let first = get_first_char(name)
      if first >= 'a' && first <= 'z' {
        resolve_type_alias("JsValue", type_aliases)
      } else {
        resolve_type_alias(name, type_aliases)
      }
    }
    Sequence(inner) => {
      let inner_type = idl_type_to_moonbit_with_aliases(inner, type_aliases)
      "Array[" + inner_type + "]"
    }
    Promise(inner) => {
      let inner_type = idl_type_to_moonbit_with_aliases(inner, type_aliases)
      resolve_type_alias("Promise", type_aliases) + "[" + inner_type + "]"
    }
    Union(_) => resolve_type_alias("JsValue", type_aliases)
    Any => resolve_type_alias("JsValue", type_aliases)
  }
}

///|
fn resolve_type_alias(type_name : String, type_aliases : Array[(String, String)]) -> String {
  for entry in type_aliases {
    if entry.0 == type_name {
      return entry.1 + "." + type_name
    }
  }
  type_name
}

///|
fn ends_with_question_v2(s : String) -> Bool {
  let mut last = ' '
  for c in s {
    last = c
  }
  last == '?'
}
