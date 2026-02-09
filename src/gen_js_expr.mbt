// JS call expression generation: argument conversion, dictionary wrappers

///|
/// Generate JS call argument expression for a single argument.
/// Handles: enum array lookup, nullable enum, nullable named type unwrap, Int64 conversion,
/// dictionary to_js conversion, and pass-through for other types.
fn gen_js_call_arg(
  arg : Argument,
  enum_map : Array[(String, Array[String])],
  dict_map : Array[(String, DictionaryDef)],
) -> String {
  let arg_name = escape_reserved(to_snake_case(arg.name))
  match arg.idl_type {
    Named(type_name) =>
      match lookup_enum(enum_map, type_name) {
        Some(values) => gen_enum_array_lookup(values, arg_name)
        None =>
          // Dictionary type: pass through (wrapper handles .to_js() conversion)
          if not(lookup_dict(dict_map, type_name) is None) {
            arg_name
          } else if is_int64_type(arg.idl_type) {
            int64_param_to_js(arg_name)
          } else {
            arg_name
          }
      }
    Nullable(Named(type_name)) =>
      match lookup_enum(enum_map, type_name) {
        Some(values) => gen_nullable_enum_array_lookup(values, arg_name)
        None =>
          // Nullable named type: unwrap from MoonBit Option[T]
          // Option[T] uses $tag:0=None, $tag:1/_0=Some (NOT Nullable enum)
          unwrap_option_named_param(arg_name)
      }
    Primitive("long long") | Primitive("unsigned long long") =>
      int64_param_to_js(arg_name)
    _ => arg_name
  }
}

///|
/// Lookup dictionary by name from dict_map
pub fn lookup_dict(
  dict_map : Array[(String, DictionaryDef)],
  name : String,
) -> DictionaryDef? {
  dict_map
  .iter()
  .fold(init=(None : DictionaryDef?), fn(found, entry) {
    match found {
      Some(_) => found
      None => if entry.0 == name { Some(entry.1) } else { None }
    }
  })
}

///|
/// Check if any argument in the list is a dictionary type
fn has_dict_args(
  args : Array[Argument],
  arg_count : Int,
  dict_map : Array[(String, DictionaryDef)],
) -> Bool {
  for i = 0; i < arg_count; i = i + 1 {
    match args[i].idl_type {
      Named(type_name) =>
        if not(lookup_dict(dict_map, type_name) is None) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
/// Get MoonBit arg type for FFI function (JsValue for dict args)
fn gen_ffi_arg_type(
  arg : Argument,
  dict_map : Array[(String, DictionaryDef)],
) -> String {
  match arg.idl_type {
    Named(type_name) =>
      if not(lookup_dict(dict_map, type_name) is None) {
        "JsValue"
      } else {
        idl_type_to_moonbit(arg.idl_type)
      }
    _ => idl_type_to_moonbit(arg.idl_type)
  }
}

///|
/// Generate wrapper call arg (name.to_js() for dict args, name for others)
fn gen_wrapper_call_arg(
  arg : Argument,
  dict_map : Array[(String, DictionaryDef)],
) -> String {
  let arg_name = escape_reserved(to_snake_case(arg.name))
  match arg.idl_type {
    Named(type_name) =>
      if not(lookup_dict(dict_map, type_name) is None) {
        arg_name + ".to_js()"
      } else {
        arg_name
      }
    _ => arg_name
  }
}

///|
/// Generate dict wrapper function (pub fn that calls _ffi with .to_js() conversion)
fn gen_dict_wrapper(
  result : StringBuilder,
  full_fn_name : String,
  args : Array[Argument],
  arg_count : Int,
  return_type : String,
  dict_map : Array[(String, DictionaryDef)],
  has_self : Bool,
  interface_name : String,
) -> Unit {
  result.write_string("\npub fn ")
  result.write_string(full_fn_name)
  result.write_string("(")
  let mut first = true
  if has_self {
    result.write_string("self : ")
    result.write_string(interface_name)
    first = false
  }
  for i = 0; i < arg_count; i = i + 1 {
    if not(first) {
      result.write_string(", ")
    }
    first = false
    result.write_string(escape_reserved(to_snake_case(args[i].name)))
    result.write_string(" : ")
    result.write_string(idl_type_to_moonbit(args[i].idl_type))
  }
  result.write_string(") -> ")
  result.write_string(return_type)
  result.write_string(" {\n  ")
  result.write_string(full_fn_name)
  result.write_string("_ffi(")
  first = true
  if has_self {
    result.write_string("self")
    first = false
  }
  for i = 0; i < arg_count; i = i + 1 {
    if not(first) {
      result.write_string(", ")
    }
    first = false
    result.write_string(gen_wrapper_call_arg(args[i], dict_map))
  }
  result.write_string(")\n}\n")
}

///|
/// Remove first character from string
fn remove_leading_char(s : String) -> String {
  let chars = s.to_array()
  if chars.length() <= 1 {
    return ""
  }
  String::from_array(chars[1:])
}
