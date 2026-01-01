// Dictionary/Enum binding 生成ロジック

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
      // 二重 nullable を防ぐ（既に ? で終わっている場合はそのまま）
      if ends_with_question(inner_type) {
        inner_type
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
    Sequence(_) => "JsValue"
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
/// 文字列の最初の文字を取得
fn get_first_char_types(s : String) -> Char {
  for c in s {
    return c
  }
  ' '
}

///|
/// Dictionary から MoonBit struct を生成
pub fn gen_dictionary(dict : DictionaryDef) -> String {
  let mut result = ""

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

    // オプショナルフィールド対応
    if not(mem.required) {
      result = result + type_to_moonbit(mem.idl_type)
      result = result + "?"
    } else {
      result = result + type_to_moonbit(mem.idl_type)
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
      result = result + "None"
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
            Named(_) | Any | Sequence(_) | Union(_) =>
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
    result = result + ": self."
    // MoonBit側では変換後の名前
    result = result + moonbit_name
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
/// Enum から MoonBit enum を生成
pub fn gen_enum(enum_def : EnumDef) -> String {
  let mut result = ""

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
    | "method" => name + "_"
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

  // ドキュメントコメント
  result = result + "/// "
  result = result + typedef_def.name
  result = result + " typedef\n"

  // type alias 定義
  result = result + "pub type "
  result = result + typedef_def.name
  result = result + " = "
  result = result + type_to_moonbit(typedef_def.idl_type)
  result = result + "\n"
  result
}
