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
  }
}

///|
/// IdlType から Named 型を収集
fn collect_types_from_idl_type(t : IdlType, refs : Array[String]) -> Unit {
  match t {
    Named(name) => if not(array_contains(refs, name)) { refs.push(name) }
    Nullable(inner) => collect_types_from_idl_type(inner, refs)
    Sequence(inner) => collect_types_from_idl_type(inner, refs)
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

    // CallbackInterface を出力（opaque型として）
    for def in definitions {
      match def {
        CallbackInterface(cb) => {
          result.write_string("/// ")
          result.write_string(cb.name)
          result.write_string(" callback interface\n")
          result.write_string("pub type ")
          result.write_string(cb.name)
          result.write_string("\n\n")
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

  // Step 4: Build result array
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
/// Interface メンバーをマージ（重複検出・警告付き）
fn merge_interface_members(
  existing : Array[InterfaceMember],
  new_members : Array[InterfaceMember],
  target_name : String,
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
        // Duplicate detected - warn and skip
        println(
          "Warning: Duplicate member '" +
          new_name +
          "' in partial interface '" +
          target_name +
          "' - skipping",
        )
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
  }
}

///|
/// Dictionary メンバーをマージ（重複検出付き）
fn merge_dictionary_members(
  existing : Array[DictionaryMember],
  new_members : Array[DictionaryMember],
) -> Array[DictionaryMember] {
  let result : Array[DictionaryMember] = []

  // Copy existing members
  for mem in existing {
    result.push(mem)
  }

  // Add new members, checking for duplicates
  for new_mem in new_members {
    let mut is_duplicate = false
    for existing_mem in existing {
      if existing_mem.name == new_mem.name {
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
  result.write_string("// Shared types for web-sys\n")
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
  global_enum_map : Array[(String, Array[String])]
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

    // CallbackInterface を出力（opaque型として）
    for def in definitions {
      match def {
        CallbackInterface(cb) => {
          result.write_string("/// ")
          result.write_string(cb.name)
          result.write_string(" callback interface\n")
          result.write_string("pub type ")
          result.write_string(cb.name)
          result.write_string("\n\n")
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
      _ => {
        let type_name = get_definition_name(def)
        let owner = get_type_owner(ownership, type_name)

        // Include only if this spec owns the type
        // For Partials, type_name is the target type, so only include if we own it
        // (otherwise merge_definitions would create a duplicate Interface definition)
        if owner == spec_name {
          filtered.push(def)
        }
      }
    }
  }
  filtered
}
