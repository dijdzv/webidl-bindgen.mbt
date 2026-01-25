// コード出力フォーマッター

///|
/// ヘッダーで宣言される外部型（カテゴリ付き）
/// (型名, カテゴリ, コメント)
let external_header_types : Array[(String, String, String)] = [
  // HTML Elements
  ("HTMLCanvasElement", "HTML Elements", ""),
  ("HTMLImageElement", "HTML Elements", ""),
  ("HTMLVideoElement", "HTML Elements", ""),
  ("Element", "HTML Elements", ""),
  // SVG Elements
  ("SVGImageElement", "SVG Elements", ""),
  ("SVGMatrix", "SVG Elements", ""),
  // Canvas/Image types
  ("ImageBitmap", "Canvas/Image types", ""),
  ("ImageData", "Canvas/Image types", ""),
  ("OffscreenCanvas", "Canvas/Image types", ""),
  ("VideoFrame", "Canvas/Image types", ""),
  ("CanvasImageSource", "Canvas/Image types", "// union type"),
  ("CanvasGradient", "Canvas/Image types", ""),
  ("CanvasPattern", "Canvas/Image types", ""),
  ("Path2D", "Canvas/Image types", ""),
  // Matrix/Transform types
  ("DOMMatrix", "Matrix/Transform types", ""),
  ("DOMMatrix2DInit", "Matrix/Transform types", ""),
  // TypedArrays
  ("Uint8ClampedArray", "TypedArrays", ""),
  ("Float64Array", "TypedArrays", ""),
]

///|
/// MoonBit 組み込み型（外部型判定で除外）
let builtin_types : Array[String] = [
  "JsValue", "Int", "Int64", "Double", "Bool", "String", "Unit", "Bytes",
]

///|
/// 外部型名のみの配列を取得
fn get_external_type_names() -> Array[String] {
  external_header_types.map(fn(entry) { entry.0 })
}

///|
/// WebIDL で定義される型名を収集
fn collect_defined_types(definitions : Array[Definition]) -> Array[String] {
  definitions
  .iter()
  .filter_map(fn(def) {
    match def {
      Interface(iface) => Some(iface.name)
      Dictionary(dict) => Some(dict.name)
      Enum(e) => Some(e.name)
      Typedef(t) => Some(t.name)
      CallbackInterface(cb) => Some(cb.name)
      _ => None
    }
  })
  .collect()
}

///|
/// 定義内で参照されている型名を収集
fn collect_referenced_types(definitions : Array[Definition]) -> Array[String] {
  let refs : Array[String] = []
  definitions
  .iter()
  .each(fn(def) {
    match def {
      Interface(iface) =>
        iface.members
        .iter()
        .each(fn(mem) { collect_types_from_member(mem, refs) })
      Dictionary(dict) =>
        dict.members
        .iter()
        .each(fn(mem) { collect_types_from_idl_type(mem.idl_type, refs) })
      Typedef(t) => collect_types_from_idl_type(t.idl_type, refs)
      Partial(p) =>
        p.members.iter().each(fn(mem) { collect_types_from_member(mem, refs) })
      _ => ()
    }
  })
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
      op.arguments
      .iter()
      .each(fn(arg) { collect_types_from_idl_type(arg.idl_type, refs) })
    }
    Attribute(attr) => collect_types_from_idl_type(attr.idl_type, refs)
    Const(c) => collect_types_from_idl_type(c.idl_type, refs)
    Constructor(ctor) =>
      ctor.arguments
      .iter()
      .each(fn(arg) { collect_types_from_idl_type(arg.idl_type, refs) })
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
    Named(name) => if not(refs.contains(name)) { refs.push(name) }
    Nullable(inner) => collect_types_from_idl_type(inner, refs)
    Sequence(inner) => collect_types_from_idl_type(inner, refs)
    Promise(inner) => collect_types_from_idl_type(inner, refs)
    Union(types) =>
      types.iter().each(fn(ut) { collect_types_from_idl_type(ut, refs) })
    _ => ()
  }
}

///|
/// 全定義から inline Union を収集
pub fn collect_inline_unions(
  definitions : Array[Definition],
) -> InlineUnionCollector {
  let collector = InlineUnionCollector::new()
  definitions
  .iter()
  .each(fn(def) {
    match def {
      Interface(iface) =>
        iface.members
        .iter()
        .each(fn(mem) { collect_inline_unions_from_member(mem, collector) })
      InterfaceMixin(mixin_def) =>
        mixin_def.members
        .iter()
        .each(fn(mem) { collect_inline_unions_from_member(mem, collector) })
      Dictionary(dict) =>
        dict.members
        .iter()
        .each(fn(mem) {
          collect_inline_unions_from_idl_type(mem.idl_type, collector)
        })
      Partial(p) =>
        p.members
        .iter()
        .each(fn(mem) { collect_inline_unions_from_member(mem, collector) })
      CallbackInterface(cb) => {
        // callback の引数を処理
        cb.arguments
        .iter()
        .each(fn(arg) {
          collect_inline_unions_from_idl_type(arg.idl_type, collector)
        })
        // callback の戻り値を処理
        match cb.return_type {
          Some(t) => collect_inline_unions_from_idl_type(t, collector)
          None => ()
        }
      }
      _ => ()
    }
  })
  collector
}

///|
/// InterfaceMember から inline Union を収集
fn collect_inline_unions_from_member(
  mem : InterfaceMember,
  collector : InlineUnionCollector,
) -> Unit {
  match mem {
    Operation(op) => {
      collect_inline_unions_from_idl_type(op.return_type, collector)
      op.arguments
      .iter()
      .each(fn(arg) {
        collect_inline_unions_from_idl_type(arg.idl_type, collector)
      })
    }
    Attribute(attr) =>
      collect_inline_unions_from_idl_type(attr.idl_type, collector)
    Constructor(ctor) =>
      ctor.arguments
      .iter()
      .each(fn(arg) {
        collect_inline_unions_from_idl_type(arg.idl_type, collector)
      })
    Maplike(m) => {
      collect_inline_unions_from_idl_type(m.key_type, collector)
      collect_inline_unions_from_idl_type(m.value_type, collector)
    }
    Setlike(s) => collect_inline_unions_from_idl_type(s.value_type, collector)
    _ => ()
  }
}

///|
/// IdlType から inline Union を収集
fn collect_inline_unions_from_idl_type(
  t : IdlType,
  collector : InlineUnionCollector,
) -> Unit {
  match t {
    Nullable(inner) => collect_inline_unions_from_idl_type(inner, collector)
    Sequence(inner) => collect_inline_unions_from_idl_type(inner, collector)
    Promise(inner) => collect_inline_unions_from_idl_type(inner, collector)
    Union(members) => {
      // 1メンバーの Union はスキップ（その型を直接使う）
      if members.length() == 1 {
        collect_inline_unions_from_idl_type(members[0], collector)
        return
      }
      // inline Union を収集（idl_type_to_moonbit_collecting を使用）
      let dummy_collector = InlineUnionCollector::new()
      let _ = idl_type_to_moonbit_collecting(t, dummy_collector)
      // dummy_collector に追加されたものを本体コレクタにマージ
      dummy_collector
      .iter()
      .filter(fn(entry) {
        not(has_inline_union_in_collector(collector, entry.0))
      })
      .each(fn(entry) { collector.push(entry) })
      // Union メンバーも再帰的に処理
      members
      .iter()
      .each(fn(mem) { collect_inline_unions_from_idl_type(mem, collector) })
    }
    _ => ()
  }
}

///|
/// コレクタに指定名の Union が存在するかチェック
fn has_inline_union_in_collector(
  collector : InlineUnionCollector,
  name : String,
) -> Bool {
  collector.iter().any(fn(entry) { entry.0 == name })
}

///|
/// 未定義の外部型を抽出（ownership map から定義済み型を除外するバージョン）
pub fn collect_external_types_with_ownership(
  definitions : Array[Definition],
  ownership : Array[(String, String)],
) -> Array[String] {
  let referenced = collect_referenced_types(definitions)
  referenced
  .iter()
  .fold(init=Array::new(), fn(undefined, ref_type) {
    // 小文字始まりは除外 (object など無効な型名)
    let first_char = get_first_char(ref_type)
    let is_lowercase = first_char >= 'a' && first_char <= 'z'
    // ownership map で定義済みかチェック
    let is_defined = ownership.iter().any(fn(entry) { entry.0 == ref_type })
    if not(is_defined) &&
      not(builtin_types.contains(ref_type)) &&
      not(undefined.contains(ref_type)) &&
      not(is_lowercase) {
      undefined.push(ref_type)
    }
    undefined
  })
}

///|
/// 未定義の外部型を抽出
fn collect_undefined_external_types(
  definitions : Array[Definition],
) -> Array[String] {
  let defined = collect_defined_types(definitions)
  let referenced = collect_referenced_types(definitions)
  // ヘッダーで既に宣言される型も除外
  let header_types = get_external_type_names()
  referenced
  .iter()
  .fold(init=Array::new(), fn(undefined, ref_type) {
    // 小文字始まりは除外 (object など無効な型名)
    let first_char = get_first_char(ref_type)
    let is_lowercase = first_char >= 'a' && first_char <= 'z'
    if not(defined.contains(ref_type)) &&
      not(builtin_types.contains(ref_type)) &&
      not(header_types.contains(ref_type)) &&
      not(undefined.contains(ref_type)) &&
      not(is_lowercase) {
      undefined.push(ref_type)
    }
    undefined
  })
}

///|
/// 型名が除外リストに含まれるかチェック
fn is_excluded_type(name : String, exclude : Array[String]) -> Bool {
  exclude.contains(name)
}

///|
/// 外部型を出力（除外リストにない場合のみ）
/// 型が出力されたかを返す
fn write_external_type(
  result : StringBuilder,
  name : String,
  exclude : Array[String],
  comment : String,
) -> Bool {
  if not(is_excluded_type(name, exclude)) {
    result.write_string("pub type ")
    result.write_string(name)
    if comment != "" {
      result.write_string("  ")
      result.write_string(comment)
    }
    result.write_string("\n")
    return true
  }
  false
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
  ignore(write_external_type(result, "JsValue", exclude, ""))
  result.write_string("\n")

  // JsValue helper functions
  result.write_string(
    "pub extern \"js\" fn JsValue::undefined() -> JsValue =\n",
  )
  result.write_string("  #| () => undefined\n\n")

  // JsValue type check methods
  result.write_string("/// Check if value is null\n")
  result.write_string(
    "pub extern \"js\" fn JsValue::is_null(self : JsValue) -> Bool =\n",
  )
  result.write_string("  #| (self) => self === null\n\n")
  result.write_string("/// Check if value is undefined\n")
  result.write_string(
    "pub extern \"js\" fn JsValue::is_undefined(self : JsValue) -> Bool =\n",
  )
  result.write_string("  #| (self) => self === undefined\n\n")
  result.write_string("/// Check if value is null or undefined\n")
  result.write_string(
    "pub extern \"js\" fn JsValue::is_null_or_undefined(self : JsValue) -> Bool =\n",
  )
  result.write_string("  #| (self) => self == null\n\n")

  // Promise type (WebIDL built-in) - aliased to @js_async.Promise for .wait() support
  result.write_string(
    "/// JavaScript Promise type (aliased to @js_async.Promise)\n",
  )
  result.write_string("pub type Promise[T] = @js_async.Promise[T]\n\n")

  // 外部型をカテゴリごとに出力（型がある場合のみヘッダーを出力）
  ignore(
    external_header_types
    .iter()
    .fold(
      init=("", false), // (current_category, header_written)
      fn(state, entry) {
        let (current_category, header_written) = state
        let (type_name, category, comment) = entry
        if category != current_category {
          // 新しいカテゴリに入った
          if not(is_excluded_type(type_name, exclude)) {
            // 型が出力される場合、ヘッダーを出力
            if current_category != "" {
              result.write_string("\n")
            }
            result.write_string("// ")
            result.write_string(category)
            result.write_string("\n")
            ignore(write_external_type(result, type_name, exclude, comment))
            (category, true)
          } else {
            // 型が除外される場合、ヘッダーは出力しない
            (category, false)
          }
          // 同じカテゴリ内
        } else if not(header_written) &&
          not(is_excluded_type(type_name, exclude)) {
          // このカテゴリで初めて出力する型なのでヘッダーを出力
          if current_category != "" {
            result.write_string("\n")
          }
          result.write_string("// ")
          result.write_string(category)
          result.write_string("\n")
          ignore(write_external_type(result, type_name, exclude, comment))
          (category, true)
        } else {
          ignore(write_external_type(result, type_name, exclude, comment))
          (category, header_written)
        }
      },
    ),
  )
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
  let title_len = title.length()
  let padding = (line_len - title_len - 4) / 2
  // パディング文字を書き込み
  for _ in 0..<padding {
    result.write_char('-')
  }
  result.write_string(" ")
  result.write_string(title)
  result.write_string(" ")
  for _ in 0..<padding {
    result.write_char('-')
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

  // Dictionary型の名前を収集（Union の is_*/as_* で使用）
  let dictionary_names : Array[String] = definitions
    .iter()
    .filter_map(fn(def) {
      match def {
        Dictionary(d) => Some(d.name)
        _ => None
      }
    })
    .collect()

  // ファイルヘッダー（WebIDL で定義される型は除外）
  result.write_string(gen_file_header_with_exclude(source_file, defined_types))

  // 未定義の外部型を宣言
  let undefined_types = collect_undefined_external_types(definitions)
  if undefined_types.length() > 0 {
    result.write_string(
      "// Referenced external types (not defined in this WebIDL)\n",
    )
    undefined_types
    .iter()
    .each(fn(type_name) {
      result.write_string("pub type ")
      result.write_string(type_name)
      result.write_string("\n")
    })
    result.write_string("\n")
  }

  // enum マップを作成（enum 引数の文字列変換に使用）
  let enum_map : Array[(String, Array[String])] = []
  // enum 名リストを作成（instanceof -> typeof === 'string'）
  let enum_names : Array[String] = []
  // Union 型セットを作成（to_js で .to_js_value() 呼び出しに使用）
  let union_set : Array[String] = []
  // Union typedef マップを作成（is_*/as_* の型チェックで使用）
  let union_typedef_map : Array[(String, Array[IdlType])] = []
  // プリミティブ typedef マップを作成（instanceof -> typeof check）
  let primitive_typedef_map : Array[(String, IdlType)] = []
  // callback interface 名リストを作成（instanceof -> typeof === 'function'）
  let callback_interface_names : Array[String] = []
  definitions
  .iter()
  .each(fn(def) {
    match def {
      Enum(e) => {
        enum_map.push((e.name, e.values))
        enum_names.push(e.name)
      }
      Typedef(t) =>
        match t.idl_type {
          Union(members) => {
            union_set.push(t.name)
            union_typedef_map.push((t.name, members))
          }
          other => primitive_typedef_map.push((t.name, other))
        }
      CallbackInterface(cb) => callback_interface_names.push(cb.name)
      _ => ()
    }
  })

  // inline Union を収集
  let inline_unions = collect_inline_unions(definitions)
  // inline Union 名を union_set に追加
  inline_unions
  .iter()
  .filter(fn(entry) { not(union_set.contains(entry.0)) })
  .each(fn(entry) { union_set.push(entry.0) })

  // Types セクション (enum, dictionary, typedef, callback interface, inline unions)
  let has_types = inline_unions.length() > 0 ||
    definitions
    .iter()
    .any(fn(def) {
      match def {
        Enum(_) | Dictionary(_) | Typedef(_) | CallbackInterface(_) => true
        _ => false
      }
    })
  if has_types {
    result.write_string(gen_section_comment("Types"))

    // Typedef を先に出力（他の型から参照される可能性があるため）
    definitions
    .iter()
    .each(fn(def) {
      match def {
        Typedef(t) => {
          result.write_string(
            gen_typedef(
              t,
              dictionary_names~,
              union_typedef_map~,
              enum_names~,
              primitive_typedef_map~,
              callback_interface_names~,
            ),
          )
          result.write_string("\n")
        }
        _ => ()
      }
    })

    // inline Union の typedef を出力
    inline_unions
    .iter()
    .each(fn(entry) {
      let (name, members) = entry
      // TypedefDef を作成して gen_typedef を再利用
      let typedef_def : TypedefDef = { name, idl_type: Union(members) }
      result.write_string(
        gen_typedef(
          typedef_def,
          dictionary_names~,
          union_typedef_map~,
          enum_names~,
          primitive_typedef_map~,
          callback_interface_names~,
        ),
      )
      result.write_string("\n")
    })

    // Enum を出力
    definitions
    .iter()
    .each(fn(def) {
      match def {
        Enum(e) => {
          result.write_string(gen_enum(e))
          result.write_string("\n")
        }
        _ => ()
      }
    })

    // CallbackInterface を出力（opaque型 + from_fn ヘルパー）
    definitions
    .iter()
    .each(fn(def) {
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
    })

    // Dictionary を出力
    definitions
    .iter()
    .each(fn(def) {
      match def {
        Dictionary(d) => {
          result.write_string(gen_dictionary(d, enum_map, union_set))
          result.write_string("\n")
        }
        _ => ()
      }
    })
  }

  // Interfaces セクション
  // まず interfaces 配列を構築（upcast/downcast メソッド生成に使用）
  let interfaces : Array[(String, InterfaceDef)] = definitions
    .iter()
    .filter_map(fn(def) {
      match def {
        Interface(iface) => Some((iface.name, iface))
        _ => None
      }
    })
    .collect()

  // 継承マップを構築（downcast メソッド生成に使用）
  let inheritance_map = build_inheritance_map(interfaces)
  let has_interfaces = interfaces.length() > 0
  if has_interfaces {
    result.write_string(gen_section_comment("Interfaces"))
    interfaces
    .iter()
    .each(fn(entry) {
      let (_, iface) = entry
      result.write_string(
        gen_interface_binding(iface, enum_map, interfaces~, inheritance_map~),
      )
      result.write_string("\n")
    })
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
  let current_line = StringBuilder::new()
  // State: (prev_was_blank, current_line)
  let (_, final_line) = code
    .iter()
    .fold(init=(false, current_line), fn(state, c) {
      let (prev_was_blank, current_line) = state
      if c == '\n' {
        let line = current_line.to_string()
        let is_blank = is_blank_line(line)
        if is_blank {
          if not(prev_was_blank) {
            result.write_char('\n')
          }
          (true, StringBuilder::new())
        } else {
          result.write_string(line)
          result.write_char('\n')
          (false, StringBuilder::new())
        }
      } else {
        current_line.write_char(c)
        (prev_was_blank, current_line)
      }
    })

  // 最後の行を処理
  let last_line = final_line.to_string()
  if not(is_blank_line(last_line)) {
    result.write_string(last_line)
  }
  result.to_string()
}

///|
/// 空白行かどうか判定
fn is_blank_line(line : String) -> Bool {
  line.iter().all(fn(c) { c == ' ' || c == '\t' })
}

///|
/// インデントを正規化（タブをスペース2つに変換）
pub fn normalize_indent(code : String) -> String {
  let result = StringBuilder::new()
  code
  .iter()
  .each(fn(c) {
    if c == '\t' {
      result.write_string("  ")
    } else {
      result.write_char(c)
    }
  })
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

///|
/// 共通型定義を生成（per-spec モード用）
/// dictionary_names: Dictionary型の名前リスト（Union の is_*/as_* で使用）
/// union_typedef_map: Union typedef名から構成要素へのマップ
/// enum_names: enum型の名前リスト（instanceof -> typeof === 'string'）
/// primitive_typedef_map: プリミティブtypedef名から解決後の型へのマップ
/// callback_interface_names: callback interface型の名前リスト（instanceof -> typeof === 'function'）
pub fn gen_shared_types_with_externals(
  external_types : Array[String],
  inline_unions : InlineUnionCollector,
  defined_types : Array[String],
  dictionary_names : Array[String],
  union_typedef_map? : Array[(String, Array[IdlType])] = [],
  enum_names? : Array[String] = [],
  primitive_typedef_map? : Array[(String, IdlType)] = [],
  callback_interface_names? : Array[String] = [],
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

  // Promise type (WebIDL built-in) - aliased to @js_async.Promise for .wait() support
  result.write_string(
    "/// JavaScript Promise type (aliased to @js_async.Promise)\n",
  )
  result.write_string("pub type Promise[T] = @js_async.Promise[T]\n\n")

  // Nullable type for JavaScript null vs undefined distinction
  result.write_string(
    "/// Nullable type for distinguishing null from undefined\n",
  )
  result.write_string("/// - Undefined: property not set (JS undefined)\n")
  result.write_string("/// - Null: explicitly null\n")
  result.write_string("/// - Value(T): has a value\n")
  result.write_string("pub enum Nullable[T] {\n")
  result.write_string("  Undefined\n")
  result.write_string("  Null\n")
  result.write_string("  Value(T)\n")
  result.write_string("}\n\n")

  // External type declarations
  if external_types.length() > 0 {
    result.write_string(
      "// External types (referenced but not defined in WebIDL specs)\n",
    )
    external_types
    .iter()
    .each(fn(ext_type) {
      result.write_string("pub type ")
      result.write_string(ext_type)
      result.write_string("\n")
    })
    result.write_string("\n")
  }

  // Inline Union type definitions
  if inline_unions.length() > 0 {
    result.write_string("// Inline Union types\n")
    inline_unions
    .iter()
    .filter(fn(entry) { not(defined_types.contains(entry.0)) })
    .each(fn(entry) {
      let (name, members) = entry
      // Generate typedef for each inline Union
      let typedef_def : TypedefDef = { name, idl_type: Union(members) }
      result.write_string(
        gen_typedef(
          typedef_def,
          dictionary_names~,
          union_typedef_map~,
          enum_names~,
          primitive_typedef_map~,
          callback_interface_names~,
        ),
      )
      result.write_string("\n")
    })
  }

  // JsValue type check methods
  result.write_string("// JsValue type checks\n")
  result.write_string("/// Check if value is null\n")
  result.write_string(
    "pub extern \"js\" fn JsValue::is_null(self : JsValue) -> Bool =\n",
  )
  result.write_string("  #| (self) => self === null\n\n")
  result.write_string("/// Check if value is undefined\n")
  result.write_string(
    "pub extern \"js\" fn JsValue::is_undefined(self : JsValue) -> Bool =\n",
  )
  result.write_string("  #| (self) => self === undefined\n\n")
  result.write_string("/// Check if value is null or undefined\n")
  result.write_string(
    "pub extern \"js\" fn JsValue::is_null_or_undefined(self : JsValue) -> Bool =\n",
  )
  result.write_string("  #| (self) => self == null\n\n")

  // TypedArray index access methods
  result.write_string("// TypedArray index access\n")
  // Uint8ClampedArray
  result.write_string(
    "pub extern \"js\" fn Uint8ClampedArray::op_get(self : Uint8ClampedArray, index : Int) -> Int =\n",
  )
  result.write_string("  #| (self, index) => self[index]\n\n")
  result.write_string(
    "pub extern \"js\" fn Uint8ClampedArray::op_set(self : Uint8ClampedArray, index : Int, value : Int) -> Unit =\n",
  )
  result.write_string(
    "  #| (self, index, value) => { self[index] = value }\n\n",
  )
  result.write_string(
    "pub extern \"js\" fn Uint8ClampedArray::length(self : Uint8ClampedArray) -> Int =\n",
  )
  result.write_string("  #| (self) => self.length\n\n")
  // Float64Array
  result.write_string(
    "pub extern \"js\" fn Float64Array::op_get(self : Float64Array, index : Int) -> Double =\n",
  )
  result.write_string("  #| (self, index) => self[index]\n\n")
  result.write_string(
    "pub extern \"js\" fn Float64Array::op_set(self : Float64Array, index : Int, value : Double) -> Unit =\n",
  )
  result.write_string(
    "  #| (self, index, value) => { self[index] = value }\n\n",
  )
  result.write_string(
    "pub extern \"js\" fn Float64Array::length(self : Float64Array) -> Int =\n",
  )
  result.write_string("  #| (self) => self.length\n\n")

  // Global accessor functions
  if defined_types.contains("Window") {
    result.write_string("// Global accessors\n")
    result.write_string("/// Get the global window object\n")
    result.write_string("pub extern \"js\" fn window() -> Window? =\n")
    result.write_string(
      "  #| () => (typeof window !== 'undefined') ? { $tag: 1, _0: window } : { $tag: 0 }\n\n",
    )
  }
  result.to_string()
}

///|
/// 仕様ごとのフォーマット出力（外部型宣言なし）
/// dictionary_names: Dictionary型の名前リスト（Union の is_*/as_* で使用）
/// union_typedef_map: Union typedef名から構成要素へのマップ
/// enum_names: enum型の名前リスト（instanceof -> typeof === 'string'）
/// primitive_typedef_map: プリミティブtypedef名から解決後の型へのマップ
/// callback_interface_names: callback interface型の名前リスト（instanceof -> typeof === 'function'）
pub fn format_spec_output(
  spec_name : String,
  definitions : Array[Definition],
  global_enum_map : Array[(String, Array[String])],
  global_union_set : Array[String],
  dictionary_names : Array[String],
  union_typedef_map? : Array[(String, Array[IdlType])] = [],
  enum_names? : Array[String] = [],
  primitive_typedef_map? : Array[(String, IdlType)] = [],
  callback_interface_names? : Array[String] = [],
  global_interfaces? : Array[(String, InterfaceDef)] = [],
  global_inheritance_map? : Array[(String, Array[String])] = [],
) -> String {
  let result = StringBuilder::new()

  // Header
  result.write_string("// Generated from WebIDL - DO NOT EDIT\n")
  result.write_string("// Source: @webref/idl/")
  result.write_string(spec_name)
  result.write_string("\n\n")

  // Types セクション (typedef, enum, callback interface, dictionary)
  // Note: inline Unions are generated in shared.mbt to avoid duplication
  let has_types = definitions
    .iter()
    .any(fn(def) {
      match def {
        Typedef(_) | Enum(_) | Dictionary(_) | CallbackInterface(_) => true
        _ => false
      }
    })
  if has_types {
    // Typedef を先に出力
    definitions
    .iter()
    .each(fn(def) {
      match def {
        Typedef(t) => {
          result.write_string(
            gen_typedef(
              t,
              dictionary_names~,
              union_typedef_map~,
              enum_names~,
              primitive_typedef_map~,
              callback_interface_names~,
            ),
          )
          result.write_string("\n")
        }
        _ => ()
      }
    })

    // Enum を出力
    definitions
    .iter()
    .each(fn(def) {
      match def {
        Enum(e) => {
          result.write_string(gen_enum(e))
          result.write_string("\n")
        }
        _ => ()
      }
    })

    // CallbackInterface を出力（opaque型 + from_fn ヘルパー）
    definitions
    .iter()
    .each(fn(def) {
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
    })

    // Dictionary を出力
    definitions
    .iter()
    .each(fn(def) {
      match def {
        Dictionary(d) => {
          result.write_string(
            gen_dictionary(d, global_enum_map, global_union_set),
          )
          result.write_string("\n")
        }
        _ => ()
      }
    })
  }

  // Interfaces セクション
  // この仕様の interfaces を抽出
  let spec_interfaces : Array[(String, InterfaceDef)] = definitions
    .iter()
    .filter_map(fn(def) {
      match def {
        Interface(iface) => Some((iface.name, iface))
        _ => None
      }
    })
    .collect()

  // グローバル interfaces と inheritance_map を使用（異なる仕様間の継承関係をサポート）
  spec_interfaces
  .iter()
  .each(fn(entry) {
    let (_, iface) = entry
    result.write_string(
      gen_interface_binding(
        iface,
        global_enum_map,
        interfaces=global_interfaces,
        inheritance_map=global_inheritance_map,
      ),
    )
    result.write_string("\n")
  })
  let code = result.to_string()
  let code = normalize_indent(code)
  let code = normalize_blank_lines(code)
  code
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
  ignore(
    cb.arguments
    .iter()
    .fold(init=true, fn(first, arg) {
      if not(first) {
        result.write_string(", ")
      }
      result.write_string(idl_type_to_moonbit(arg.idl_type))
      false
    }),
  )

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
