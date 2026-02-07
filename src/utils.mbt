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

// --- Option (built-in type) JS representation helpers ---
//
// MoonBit's JS backend uses different representations for Option depending on
// the inner type:
//   - String?, Bool?, Int? etc. (primitives): undefined = None, raw value = Some
//   - UserType? (opaque/named types): { $tag: 0 } = None, { $tag: 1, _0: v } = Some

///|
/// Check if an IdlType uses the primitive Option representation (undefined/value)
/// vs the tagged representation ({ $tag: 0/1 })
pub fn is_primitive_option_type(inner_type : IdlType) -> Bool {
  match inner_type {
    String => true
    Primitive(_) => true
    _ => false
  }
}

///|
/// Build JS expression for Option::Some in extern "js" return context
/// Used for user-defined types (instanceof checks, union casts)
/// Example: js_some("self") => "{ $tag: 1, _0: self }"
pub fn js_some(value_expr : String) -> String {
  "{ $tag: 1, _0: " + value_expr + " }"
}

///|
/// Build JS expression for Option::None in extern "js" return context
/// Used for user-defined types (instanceof checks, union casts)
/// Example: js_none() => "{ $tag: 0 }"
pub fn js_none() -> String {
  "{ $tag: 0 }"
}

///|
/// Wrap a JS call expression to handle nullable return types.
/// Converts JS null/undefined to the correct MoonBit Option representation.
/// For non-nullable types, returns the expression unchanged.
pub fn wrap_nullable_return(js_expr : String, return_type : IdlType) -> String {
  match return_type {
    Nullable(inner) =>
      if is_primitive_option_type(inner) {
        // String?, Bool?, Int?: convert null to undefined (MoonBit's None for primitives)
        "(" + js_expr + ") ?? undefined"
      } else {
        // User-defined type?: wrap with $tag
        "(() => { const v = " +
        js_expr +
        "; return v == null ? { $tag: 0 } : { $tag: 1, _0: v }; })()"
      }
    _ => js_expr
  }
}

///|
/// Build JS IIFE to convert Option field to JS value (Some → value, None → undefined)
/// Example: js_option_to_js("field", "v._0") =>
///   "((() => { const v = self.field; if (v.$tag !== 1) return undefined; return v._0; })())"
pub fn js_option_to_js(field_name : String, payload_expr : String) -> String {
  "((() => { const v = self." +
  field_name +
  "; if (v.$tag !== 1) return undefined; return " +
  payload_expr +
  "; })())"
}

// --- Nullable (user-defined enum) JS representation helpers ---

///|
/// Build JS check part for Nullable enum (Undefined=$tag:0, Null=$tag:1, Value=$tag:2)
/// Example: js_nullable_check("v") =>
///   "if (v.$tag === 0) return undefined; if (v.$tag === 1) return null; "
pub fn js_nullable_check(var_name : String) -> String {
  "if (" +
  var_name +
  ".$tag === 0) return undefined; if (" +
  var_name +
  ".$tag === 1) return null; "
}

///|
/// Get JS payload expression from Nullable Value variant
/// Example: js_nullable_payload("v") => "v.$0"
pub fn js_nullable_payload(var_name : String) -> String {
  var_name + ".$0"
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
