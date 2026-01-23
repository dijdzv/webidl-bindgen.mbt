// 共通ユーティリティ関数

///|
/// 文字列が ? で終わるかチェック
pub fn ends_with_question(s : String) -> Bool {
  s.to_array().last() == Some('?')
}

///|
/// 文字列の最初の文字を取得
pub fn get_first_char(s : String) -> Char {
  s.to_array().get(0).unwrap_or(' ')
}

///|
/// 文字列の末尾の ? を削除
pub fn remove_trailing_question(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  if len <= 1 {
    return ""
  }
  String::from_array(chars[:len - 1])
}

///|
/// snake_case に変換（ハイフンもアンダースコアに変換）
pub fn to_snake_case(name : String) -> String {
  let result = StringBuilder::new()
  let mut first = true
  for c in name {
    if c >= 'A' && c <= 'Z' {
      if not(first) {
        result.write_char('_')
      }
      // 大文字を小文字に変換 (ASCII: 'A'=65, 'a'=97, diff=32)
      let lower_code = c.to_int() + 32
      let lower = lower_code.unsafe_to_char()
      result.write_char(lower)
    } else if c == '-' {
      // ハイフンはアンダースコアに変換
      result.write_char('_')
    } else {
      result.write_char(c)
    }
    first = false
  }
  result.to_string()
}

///|
/// 文字列を PascalCase に変換
pub fn to_pascal_case(s : String) -> String {
  // 空文字列は "Empty" にマップ
  if s.is_empty() {
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
/// WebIDL プリミティブ型を MoonBit 型に変換
/// 未知のプリミティブは警告を出して "JsValue" を返す
pub fn primitive_to_moonbit(name : String) -> String {
  match name {
    "boolean" => "Bool"
    "byte" | "octet" | "short" | "unsigned short" | "long" | "unsigned long" =>
      "Int"
    "long long" | "unsigned long long" => "Int64"
    "float" | "unrestricted float" | "double" | "unrestricted double" =>
      "Double"
    _ => {
      println("Warning: Unknown primitive type '\{name}', using JsValue")
      "JsValue"
    }
  }
}
