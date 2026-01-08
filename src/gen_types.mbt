// Dictionary/Enum binding 生成ロジック

///|
/// enum マップから値リストを取得（Dictionary 生成用）
fn lookup_enum_values(
  enum_map : Array[(String, Array[String])],
  name : String,
) -> Array[String]? {
  for pair in enum_map {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// WebIDL 型を MoonBit 型に変換（gen_interface.mbt と共通だが重複定義）
fn type_to_moonbit(idl_type : IdlType) -> String {
  match idl_type {
    Primitive(name) =>
      match name {
        "boolean" => "Bool"
        "byte"
        | "octet"
        | "short"
        | "unsigned short"
        | "long"
        | "unsigned long" => "Int"
        "long long" | "unsigned long long" => "Int64"
        "float" | "unrestricted float" | "double" | "unrestricted double" =>
          "Double"
        _ => "JsValue"
      }
    String => "String"
    Void => "Unit"
    Nullable(inner) => {
      let inner_type = type_to_moonbit(inner)
      // 二重 nullable の場合は Nullable[T] に変換
      if ends_with_question(inner_type) {
        // T? が来た → Nullable[T] に変換
        let base_type = remove_trailing_question(inner_type)
        "Nullable[" + base_type + "]"
      } else {
        inner_type + "?"
      }
    }
    Named(name) => {
      // 小文字始まりの型名は JsValue に変換（object など無効な型名）
      let first_char = get_first_char_types(name)
      if first_char >= 'a' && first_char <= 'z' {
        "JsValue"
      } else {
        name
      }
    }
    Sequence(inner) => {
      let inner_type = type_to_moonbit(inner)
      "Array[" + inner_type + "]"
    }
    Promise(inner) => {
      let inner_type = type_to_moonbit(inner)
      "Promise[" + inner_type + "]"
    }
    Union(_) => "JsValue"
    Any => "JsValue"
  }
}

///|
/// 文字列が ? で終わるかチェック
fn ends_with_question(s : String) -> Bool {
  let mut last_char = ' '
  for c in s {
    last_char = c
  }
  last_char == '?'
}

///|
/// 文字列の末尾の ? を削除
fn remove_trailing_question(s : String) -> String {
  let result = StringBuilder::new()
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  // 最後の文字を除いて追加
  for i = 0; i < chars.length() - 1; i = i + 1 {
    result.write_char(chars[i])
  }
  result.to_string()
}

///|
/// 文字列の最初の文字を取得
fn get_first_char_types(s : String) -> Char {
  for c in s {
    return c
  }
  ' '
}

///|
/// Dictionary から MoonBit struct を生成
pub fn gen_dictionary(dict : DictionaryDef, enum_map : Array[(String, Array[String])]) -> String {
  let mut result = ""

  // セグメント分割マーカー（大きなファイルでの65535行制限回避）
  result = result + "///|\n"

  // ドキュメントコメント
  result = result + "/// "
  result = result + dict.name
  result = result + " dictionary\n"

  // struct 定義
  result = result + "pub struct "
  result = result + dict.name
  result = result + " {\n"
  for mem in dict.members {
    result = result + "  "
    result = result + field_name_to_moonbit(mem.name)
    result = result + " : "

    let moonbit_type = type_to_moonbit(mem.idl_type)
    // オプショナルフィールド対応
    if not(mem.required) {
      // 二重 nullable の場合（型がすでに ? で終わる）は Nullable[T] に変換
      if ends_with_question(moonbit_type) {
        let base_type = remove_trailing_question(moonbit_type)
        result = result + "Nullable[" + base_type + "]"
      } else {
        result = result + moonbit_type + "?"
      }
    } else {
      result = result + moonbit_type
    }
    result = result + "\n"
  }
  result = result + "}\n\n"

  // デフォルトコンストラクタ生成
  result = result + "/// Create a new "
  result = result + dict.name
  result = result + " with default values\n"
  result = result + "pub fn "
  result = result + dict.name
  result = result + "::default() -> "
  result = result + dict.name
  result = result + " {\n"
  // Use TypeName::{} syntax to disambiguate from map literal
  result = result + "  "
  result = result + dict.name
  result = result + "::{\n"
  for mem in dict.members {
    result = result + "    "
    result = result + field_name_to_moonbit(mem.name)
    result = result + ": "
    if not(mem.required) {
      // Nullable[T] 型の場合は Nullable::Undefined を使用
      let moonbit_type = type_to_moonbit(mem.idl_type)
      if ends_with_question(moonbit_type) {
        result = result + "Nullable::Undefined"
      } else {
        result = result + "None"
      }
    } else {
      // デフォルト値があれば使用
      match mem.default_value {
        Some(v) => result = result + v
        None => {
          // 型に応じたデフォルト値
          // Note: Named型には適切なデフォルト値がないため
          // この dictionary は required フィールドのデフォルト生成をスキップ
          let default_val = match mem.idl_type {
            Primitive("boolean") => "false"
            Primitive(_) => "0"
            String => "\"\""
            Nullable(_) => "None"
            Void => "()"
            Sequence(_) => "[]" // 空配列
            Named(_) | Any | Promise(_) | Union(_) =>
              // デフォルトコンストラクタでは扱えないので、
              // @json.from_json などで初期化する必要がある
              "panic()"
          }
          result = result + default_val
        }
      }
    }
    result = result + ",\n"
  }
  result = result + "  }\n"
  result = result + "}\n\n"

  // JsValue への変換関数
  result = result + "/// Convert to JsValue\n"
  result = result + "pub extern \"js\" fn "
  result = result + dict.name
  result = result + "::to_js(self : "
  result = result + dict.name
  result = result + ") -> JsValue =\n"
  result = result + "  #| (self) => ({\n"
  let members_len = dict.members.length()
  let mut idx = 0
  for mem in dict.members {
    let moonbit_name = field_name_to_moonbit(mem.name)
    result = result + "  #|   "
    // JS側では元の名前を使用
    result = result + mem.name
    result = result + ": "

    // Nullable[T] 型のフィールドかチェック
    let moonbit_type = type_to_moonbit(mem.idl_type)
    let is_nullable_type = not(mem.required) && ends_with_question(moonbit_type)

    if is_nullable_type {
      // Nullable[T] フィールドの場合は特別な JS 式を生成
      let value_expr = gen_nullable_type_field_expr(mem.idl_type, moonbit_name, enum_map)
      result = result + value_expr
    } else {
      // 通常のフィールド（enum 変換を含む）
      let value_expr = gen_field_value_expr(mem.idl_type, moonbit_name, enum_map)
      result = result + value_expr
    }

    if idx < members_len - 1 {
      result = result + ","
    }
    result = result + "\n"
    idx = idx + 1
  }
  result = result + "  #| })\n\n"
  result
}

///|
/// フィールドの値式を生成（enum の場合は配列ルックアップ、Nullable は特別処理）
fn gen_field_value_expr(
  idl_type : IdlType,
  field_name : String,
  enum_map : Array[(String, Array[String])]
) -> String {
  match idl_type {
    // 非 nullable enum フィールド
    Named(type_name) =>
      match lookup_enum_values(enum_map, type_name) {
        Some(values) => gen_enum_lookup(field_name, values)
        None => "self." + field_name
      }
    // nullable enum フィールド（単一 nullable）
    Nullable(Named(type_name)) =>
      match lookup_enum_values(enum_map, type_name) {
        Some(values) => gen_nullable_enum_lookup(field_name, values)
        None => "self." + field_name
      }
    // 二重 nullable（Nullable[T] 型）
    Nullable(Nullable(inner)) => gen_nullable_field_expr(field_name, inner, enum_map)
    // その他はそのまま
    _ => "self." + field_name
  }
}

///|
/// Nullable[T] 型フィールドの JS 式を生成
fn gen_nullable_field_expr(
  field_name : String,
  inner_type : IdlType,
  enum_map : Array[(String, Array[String])]
) -> String {
  let result = StringBuilder::new()
  result.write_string("((() => { const v = self.")
  result.write_string(field_name)
  result.write_string("; if (v.$tag === 0) return undefined; if (v.$tag === 1) return null; return ")

  // 内部型が enum の場合は変換が必要
  match inner_type {
    Named(type_name) =>
      match lookup_enum_values(enum_map, type_name) {
        Some(values) => {
          result.write_string("[")
          for i = 0; i < values.length(); i = i + 1 {
            if i > 0 {
              result.write_string(", ")
            }
            result.write_string("'")
            result.write_string(values[i])
            result.write_string("'")
          }
          result.write_string("][v.$0]")
        }
        None => result.write_string("v.$0")
      }
    _ => result.write_string("v.$0")
  }

  result.write_string("; })())")
  result.to_string()
}

///|
/// Nullable[T] 型フィールド用の JS 式を生成（optional + nullable の組み合わせ）
/// IdlType が Nullable(inner) で、かつ required=false のフィールド用
fn gen_nullable_type_field_expr(
  idl_type : IdlType,
  field_name : String,
  enum_map : Array[(String, Array[String])]
) -> String {
  // IdlType は Nullable(inner) であるはず
  let inner_type = match idl_type {
    Nullable(inner) => inner
    _ => idl_type // フォールバック
  }

  let result = StringBuilder::new()
  result.write_string("((() => { const v = self.")
  result.write_string(field_name)
  result.write_string("; if (v.$tag === 0) return undefined; if (v.$tag === 1) return null; ")

  // 内部型が enum の場合は変換が必要
  match inner_type {
    Named(type_name) =>
      match lookup_enum_values(enum_map, type_name) {
        Some(values) => {
          result.write_string("return [")
          for i = 0; i < values.length(); i = i + 1 {
            if i > 0 {
              result.write_string(", ")
            }
            result.write_string("'")
            result.write_string(values[i])
            result.write_string("'")
          }
          result.write_string("][v.$0];")
        }
        None => result.write_string("return v.$0;")
      }
    _ => result.write_string("return v.$0;")
  }

  result.write_string(" })())")
  result.to_string()
}

///|
/// 非 nullable enum 用の配列ルックアップ式を生成
fn gen_enum_lookup(field_name : String, values : Array[String]) -> String {
  let result = StringBuilder::new()
  result.write_string("[")
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string("'")
    result.write_string(values[i])
    result.write_string("'")
  }
  result.write_string("][self.")
  result.write_string(field_name)
  result.write_string("]")
  result.to_string()
}

///|
/// nullable enum 用の配列ルックアップ式を生成（null チェック付き）
fn gen_nullable_enum_lookup(field_name : String, values : Array[String]) -> String {
  let result = StringBuilder::new()
  result.write_string("(self.")
  result.write_string(field_name)
  result.write_string(" != null ? [")
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string("'")
    result.write_string(values[i])
    result.write_string("'")
  }
  result.write_string("][self.")
  result.write_string(field_name)
  result.write_string("] : null)")
  result.to_string()
}

///|
/// Enum から MoonBit enum を生成
pub fn gen_enum(enum_def : EnumDef) -> String {
  let mut result = ""

  // セグメント分割マーカー
  result = result + "///|\n"

  // ドキュメントコメント
  result = result + "/// "
  result = result + enum_def.name
  result = result + " enum\n"

  // enum 定義
  result = result + "pub(all) enum "
  result = result + enum_def.name
  result = result + " {\n"
  for value in enum_def.values {
    // 値をPascalCaseに変換
    let variant = to_pascal_case(value)
    result = result + "  "
    result = result + variant
    result = result + "\n"
  }
  result = result + "}\n\n"

  // 文字列への変換関数
  result = result + "/// Convert to string value\n"
  result = result + "pub fn "
  result = result + enum_def.name
  result = result + "::to_string(self : "
  result = result + enum_def.name
  result = result + ") -> String {\n"
  result = result + "  match self {\n"
  for value in enum_def.values {
    let variant = to_pascal_case(value)
    result = result + "    "
    result = result + variant
    result = result + " => \""
    result = result + value
    result = result + "\"\n"
  }
  result = result + "  }\n"
  result = result + "}\n\n"

  // 文字列からの変換関数
  result = result + "/// Parse from string value\n"
  result = result + "pub fn "
  result = result + enum_def.name
  result = result + "::from_string(s : String) -> "
  result = result + enum_def.name
  result = result + "? {\n"
  result = result + "  match s {\n"
  for value in enum_def.values {
    let variant = to_pascal_case(value)
    result = result + "    \""
    result = result + value
    result = result + "\" => Some("
    result = result + variant
    result = result + ")\n"
  }
  result = result + "    _ => None\n"
  result = result + "  }\n"
  result = result + "}\n"
  result
}

///|
/// 文字列を PascalCase に変換
fn to_pascal_case(s : String) -> String {
  // 空文字列は "Empty" にマップ
  if is_empty_string(s) {
    return "Empty"
  }
  let mut result = ""
  let mut capitalize_next = true
  let mut first_char = true
  for c in s {
    // セパレータ文字（次の文字を大文字化、文字自体は除去）
    if c == '-' ||
      c == '_' ||
      c == ' ' ||
      c == '/' ||
      c == '+' ||
      c == '.' ||
      c == ':' ||
      c == '*' {
      capitalize_next = true
    } else if capitalize_next {
      // 最初の文字が数字なら N を前置 (N1, N2d など)
      if first_char && c >= '0' && c <= '9' {
        result = result + "N"
        result = result + c.to_string()
        // 小文字を大文字に変換 (ASCII: 'a'=97, 'A'=65, diff=32)
      } else if c >= 'a' && c <= 'z' {
        let upper_code = c.to_int() - 32
        let upper = upper_code.unsafe_to_char()
        result = result + upper.to_string()
      } else {
        result = result + c.to_string()
      }
      capitalize_next = false
      first_char = false
    } else {
      result = result + c.to_string()
      first_char = false
    }
  }
  result
}

///|
/// 文字列が空かどうか判定
fn is_empty_string(s : String) -> Bool {
  for _ in s {
    return false
  }
  true
}

///|
/// MoonBit の予約語をエスケープ
pub fn escape_reserved(name : String) -> String {
  // MoonBit reserved keywords (including future reserved keywords that cause warnings)
  match name {
    "type"
    | "match"
    | "if"
    | "else"
    | "for"
    | "while"
    | "break"
    | "continue"
    | "return"
    | "fn"
    | "let"
    | "mut"
    | "pub"
    | "priv"
    | "struct"
    | "enum"
    | "trait"
    | "impl"
    | "self"
    | "async"
    | "await"
    | "true"
    | "false"
    | "loop"
    | "in"
    | "is"
    | "as"
    | "with"
    | "derive"
    | "test"
    | "extern"
    | "init"
    | "member"
    | "catch"
    | "guard"
    | "raise"
    | "try"
    // Future reserved keywords
    | "constructor"
    | "define"
    | "namespace"
    | "resume"
    | "finally"
    | "yield"
    | "module"
    | "alias"
    | "ref"
    | "where"
    | "method"
    | "use" => name + "_"
    _ => name
  }
}

///|
/// フィールド名を MoonBit 用に変換（小文字開始、ハイフンをアンダースコアに）
fn field_name_to_moonbit(name : String) -> String {
  let result = StringBuilder::new()
  let mut first = true
  for c in name {
    if first {
      // 最初の文字は小文字に
      if c >= 'A' && c <= 'Z' {
        let lower_code = c.to_int() + 32
        let lower = lower_code.unsafe_to_char()
        result.write_char(lower)
      } else {
        result.write_char(c)
      }
      first = false
    } else if c == '-' {
      // ハイフンはアンダースコアに
      result.write_char('_')
    } else {
      result.write_char(c)
    }
  }
  escape_reserved(result.to_string())
}

///|
/// Typedef から MoonBit type alias を生成
pub fn gen_typedef(typedef_def : TypedefDef) -> String {
  let mut result = ""

  // セグメント分割マーカー
  result = result + "///|\n"

  // ドキュメントコメント
  result = result + "/// "
  result = result + typedef_def.name
  result = result + " typedef\n"

  // Union 型の場合は opaque 型として定義（型安全なファクトリ関数のため）
  match typedef_def.idl_type {
    Union(members) => {
      // Opaque 型定義（JsValue エイリアスではない独立した型）
      result = result + "pub type "
      result = result + typedef_def.name
      result = result + "\n\n"

      // to_js_value メソッド（JS に渡すため）
      result = result + "pub extern \"js\" fn "
      result = result + typedef_def.name
      result = result + "::to_js_value(self : "
      result = result + typedef_def.name
      result = result + ") -> JsValue =\n  #| (self) => self\n\n"

      // ファクトリ関数（各メンバー型から Union 型を作成）
      for mem in members {
        let factory = gen_union_factory(typedef_def.name, mem)
        if factory != "" {
          result = result + factory
        }
      }
    }
    _ => {
      // 非 Union 型は従来通り type alias
      result = result + "pub type "
      result = result + typedef_def.name
      result = result + " = "
      result = result + type_to_moonbit(typedef_def.idl_type)
      result = result + "\n"
    }
  }

  result
}

///|
/// Union 型のファクトリ関数を生成
fn gen_union_factory(union_name : String, member_type : IdlType) -> String {
  let moonbit_type = type_to_moonbit(member_type)
  let factory_name = get_factory_name(member_type)

  // JsValue 型はスキップ（Any, Union 内 Union などの場合）
  if moonbit_type == "JsValue" || factory_name == "" {
    return ""
  }

  let result = StringBuilder::new()
  result.write_string("/// Create ")
  result.write_string(union_name)
  result.write_string(" from ")
  result.write_string(moonbit_type)
  result.write_string("\n")
  result.write_string("pub extern \"js\" fn ")
  result.write_string(union_name)
  result.write_string("::from_")
  result.write_string(factory_name)
  result.write_string("(v : ")
  result.write_string(moonbit_type)
  result.write_string(") -> ")
  result.write_string(union_name)
  result.write_string(" =\n  #| (v) => v\n\n")
  result.to_string()
}

///|
/// IdlType からファクトリ関数名を取得
fn get_factory_name(idl_type : IdlType) -> String {
  match idl_type {
    Primitive(name) =>
      match name {
        "DOMString" | "USVString" | "ByteString" => "string"
        "boolean" => "bool"
        "byte" | "octet" | "short" | "unsigned short" | "long" | "unsigned long" =>
          "int"
        "long long" | "unsigned long long" => "int64"
        "float" | "unrestricted float" | "double" | "unrestricted double" =>
          "double"
        _ => ""
      }
    String => "string"
    Named(name) => to_snake_case_factory(name)
    Sequence(inner) => {
      let inner_name = get_factory_name(inner)
      if inner_name != "" {
        "array_of_" + inner_name
      } else {
        "array"
      }
    }
    Nullable(inner) => {
      let inner_name = get_factory_name(inner)
      if inner_name != "" {
        "nullable_" + inner_name
      } else {
        ""
      }
    }
    // Void, Any, Promise, Union はファクトリを生成しない
    _ => ""
  }
}

///|
/// 型名を snake_case に変換（ファクトリ関数名用）
fn to_snake_case_factory(name : String) -> String {
  let result = StringBuilder::new()
  let mut first = true
  for c in name {
    if c >= 'A' && c <= 'Z' {
      if not(first) {
        result.write_char('_')
      }
      // 大文字を小文字に変換
      let lower_code = c.to_int() + 32
      let lower = lower_code.unsafe_to_char()
      result.write_char(lower)
    } else {
      result.write_char(c)
    }
    first = false
  }
  result.to_string()
}
