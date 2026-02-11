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
/// Pre-process identifier before snake_case conversion.
/// Handles digit+uppercase patterns like "2D" → "_2d" (same as web-sys's fix_ident).
fn fix_ident(name : String) -> String {
  let result = name
    .replace(old="1D", new="_1d")
    .replace(old="2D", new="_2d")
    .replace(old="3D", new="_3d")
  result
}

///|
/// Convert to snake_case (handles acronyms correctly)
/// Example: UIEvent -> ui_event, HTMLElement -> html_element, XMLHttpRequest -> xml_http_request
/// Example: CanvasRenderingContext2D -> canvas_rendering_context_2d
pub fn to_snake_case(name : String) -> String {
  let chars = fix_ident(name).to_array()
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
      if i > 0 && (!prev_is_upper || (prev_is_upper && next_is_lower)) {
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
  inner_type is (String | Primitive(_))
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
  "; if (v === undefined || v.$tag !== 1) return undefined; return " +
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
/// Example: js_nullable_payload("v") => "v._0"
pub fn js_nullable_payload(var_name : String) -> String {
  var_name + "._0"
}

///|
/// Unwrap an Option[Named] parameter for JS call
/// MoonBit Option: {$tag:0}=None, {$tag:1, _0:v}=Some
/// WebIDL Nullable(Named(T)) maps to MoonBit Option[T]
/// Example: unwrap_option_named_param("listener") =>
///   "(listener.$tag === 1 ? listener._0 : null)"
pub fn unwrap_option_named_param(param_name : String) -> String {
  "(" + param_name + ".$tag === 1 ? " + param_name + "._0 : null)"
}

///|
/// Unwrap a Nullable named parameter for JS call
/// MoonBit Nullable enum: {$tag:0}=Undefined, {$tag:1}=Null, {$tag:2,_0:v}=Value
/// Example: unwrap_nullable_named_param("listener") =>
///   "(listener.$tag === 2 ? listener._0 : listener.$tag === 1 ? null : undefined)"
pub fn unwrap_nullable_named_param(param_name : String) -> String {
  "(" +
  param_name +
  ".$tag === 2 ? " +
  param_name +
  "._0 : " +
  param_name +
  ".$tag === 1 ? null : undefined)"
}

///|
/// Check if an IdlType is Int64 (long long / unsigned long long)
pub fn is_int64_type(idl_type : IdlType) -> Bool {
  idl_type is (Primitive("long long") | Primitive("unsigned long long"))
}

///|
/// Wrap a JS expression to convert JS Number to MoonBit Int64 ({hi, lo} struct)
/// Example: wrap_int64_return("self.x") =>
///   "(() => { const n = self.x; return { hi: Math.floor(n / 4294967296), lo: n >>> 0 }; })()"
pub fn wrap_int64_return(js_expr : String) -> String {
  "(() => { const n = " +
  js_expr +
  "; return { hi: Math.floor(n / 4294967296), lo: n >>> 0 }; })()"
}

///|
/// Convert MoonBit Int64 parameter to JS Number expression
/// Example: int64_param_to_js("offset") => "(offset.hi * 4294967296 + offset.lo)"
pub fn int64_param_to_js(param_name : String) -> String {
  "(" + param_name + ".hi * 4294967296 + " + param_name + ".lo)"
}

///|
/// Unified return expression wrapper that handles both Int64 and Nullable returns.
/// Replaces direct calls to wrap_nullable_return in gen_interface.mbt.
pub fn wrap_return_expr(js_expr : String, return_type : IdlType) -> String {
  match return_type {
    Nullable(inner) =>
      if is_int64_type(inner) {
        // Nullable Int64: check null first, then convert to {hi, lo}
        if is_primitive_option_type(inner) {
          // Int64 is primitive, so use undefined for None
          "(() => { const v = " +
          js_expr +
          "; if (v == null) return undefined; const n = v; return { hi: Math.floor(n / 4294967296), lo: n >>> 0 }; })()"
        } else {
          "(() => { const v = " +
          js_expr +
          "; if (v == null) return { $tag: 0 }; const n = v; return { $tag: 1, _0: { hi: Math.floor(n / 4294967296), lo: n >>> 0 } }; })()"
        }
      } else {
        wrap_nullable_return(js_expr, return_type)
      }
    _ =>
      if is_int64_type(return_type) {
        wrap_int64_return(js_expr)
      } else {
        js_expr
      }
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
