// Common utility functions

///|
/// Check if string ends with ?
pub fn ends_with_question(s : String) -> Bool {
  s.to_array().last() == Some('?')
}

///|
/// Get first character of string
pub fn get_first_char(s : String) -> Char {
  s.to_array().get(0).unwrap_or(' ')
}

///|
/// Remove trailing ? from string
pub fn remove_trailing_question(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  if len <= 1 {
    return ""
  }
  String::from_array(chars[:len - 1])
}

///|
/// Convert to snake_case (handles acronyms correctly)
/// Example: UIEvent -> ui_event, HTMLElement -> html_element, XMLHttpRequest -> xml_http_request
pub fn to_snake_case(name : String) -> String {
  let chars = name.to_array()
  let len = chars.length()
  if len == 0 {
    return ""
  }
  let result = StringBuilder::new()
  for i = 0; i < len; i = i + 1 {
    let c = chars[i]
    let is_upper = c >= 'A' && c <= 'Z'
    if is_upper {
      let prev_is_upper = if i > 0 {
        let p = chars[i - 1]
        p >= 'A' && p <= 'Z'
      } else {
        false
      }
      let next_is_lower = if i + 1 < len {
        let n = chars[i + 1]
        n >= 'a' && n <= 'z'
      } else {
        false
      }
      // Conditions to insert underscore:
      // 1. Not at the beginning AND
      // 2. (previous is lowercase OR (previous is uppercase and next is lowercase))
      if i > 0 && (not(prev_is_upper) || (prev_is_upper && next_is_lower)) {
        result.write_char('_')
      }
      // Convert uppercase to lowercase
      let lower = (c.to_int() + 32).unsafe_to_char()
      result.write_char(lower)
    } else if c == '-' {
      result.write_char('_')
    } else {
      result.write_char(c)
    }
  }
  result.to_string()
}

///|
/// Convert string to PascalCase
pub fn to_pascal_case(s : String) -> String {
  if s.is_empty() {
    return "Empty"
  }
  // State: (result, capitalize_next, first_char)
  let (result, _, _) = s
    .iter()
    .fold(init=("", true, true), fn(state, c) {
      let (result, capitalize_next, first_char) = state
      // Separator characters (capitalize next character, remove the separator itself)
      if c == '-' ||
        c == '_' ||
        c == ' ' ||
        c == '/' ||
        c == '+' ||
        c == '.' ||
        c == ':' ||
        c == '*' {
        (result, true, first_char)
      } else if capitalize_next {
        // Prepend N if first character is a digit (N1, N2d, etc.)
        if first_char && c >= '0' && c <= '9' {
          (result + "N" + c.to_string(), false, false)
        } else if c >= 'a' && c <= 'z' {
          // Convert lowercase to uppercase (ASCII: 'a'=97, 'A'=65, diff=32)
          let upper = (c.to_int() - 32).unsafe_to_char()
          (result + upper.to_string(), false, false)
        } else {
          (result + c.to_string(), false, false)
        }
      } else {
        (result + c.to_string(), false, false)
      }
    })
  result
}

///|
/// Escape MoonBit reserved keywords
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
/// Convert WebIDL primitive type to MoonBit type
/// Unknown primitives print a warning and return "JsValue"
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
