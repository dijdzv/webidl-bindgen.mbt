// Code output formatter

///|
/// External types declared in header (with category)
/// (type name, category, comment)
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
/// MoonBit builtin types (excluded from external type detection)
let builtin_types : Array[String] = [
  "JsValue", "Int", "Int64", "Double", "Bool", "String", "Unit", "Bytes",
]

///|
/// Get array of external type names only
fn get_external_type_names() -> Array[String] {
  external_header_types.map(fn(entry) { entry.0 })
}

///|
/// Collect type names defined in WebIDL
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
/// Collect type names referenced in definitions
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
/// Collect types from InterfaceMember
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
/// Collect Named types from IdlType
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
/// Collect inline Unions from all definitions
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
        // Process callback arguments
        cb.arguments
        .iter()
        .each(fn(arg) {
          collect_inline_unions_from_idl_type(arg.idl_type, collector)
        })
        // Process callback return value
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
/// Collect inline Unions from InterfaceMember
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
/// Collect inline Unions from IdlType
fn collect_inline_unions_from_idl_type(
  t : IdlType,
  collector : InlineUnionCollector,
) -> Unit {
  match t {
    Nullable(inner) => collect_inline_unions_from_idl_type(inner, collector)
    Sequence(inner) => collect_inline_unions_from_idl_type(inner, collector)
    Promise(inner) => collect_inline_unions_from_idl_type(inner, collector)
    Union(members) => {
      // Skip single-member Union (use the type directly)
      if members.length() == 1 {
        collect_inline_unions_from_idl_type(members[0], collector)
        return
      }
      // Collect inline Union (using idl_type_to_moonbit_collecting)
      let dummy_collector = InlineUnionCollector::new()
      let _ = idl_type_to_moonbit_collecting(t, dummy_collector)
      // Merge items added to dummy_collector into main collector
      dummy_collector
      .iter()
      .filter(fn(entry) {
        not(has_inline_union_in_collector(collector, entry.0))
      })
      .each(fn(entry) { collector.push(entry) })
      // Process Union members recursively
      members
      .iter()
      .each(fn(mem) { collect_inline_unions_from_idl_type(mem, collector) })
    }
    _ => ()
  }
}

///|
/// Check if Union with specified name exists in collector
fn has_inline_union_in_collector(
  collector : InlineUnionCollector,
  name : String,
) -> Bool {
  collector.iter().any(fn(entry) { entry.0 == name })
}

///|
/// Extract undefined external types (version that excludes defined types using ownership map)
pub fn collect_external_types_with_ownership(
  definitions : Array[Definition],
  ownership : Array[(String, String)],
) -> Array[String] {
  let referenced = collect_referenced_types(definitions)
  referenced
  .iter()
  .fold(init=Array::new(), fn(undefined, ref_type) {
    // Exclude lowercase-starting names (invalid type names like object)
    let first_char = get_first_char(ref_type)
    let is_lowercase = first_char >= 'a' && first_char <= 'z'
    // Check if defined in ownership map
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
/// Extract undefined external types
fn collect_undefined_external_types(
  definitions : Array[Definition],
) -> Array[String] {
  let defined = collect_defined_types(definitions)
  let referenced = collect_referenced_types(definitions)
  // Also exclude types already declared in header
  let header_types = get_external_type_names()
  referenced
  .iter()
  .fold(init=Array::new(), fn(undefined, ref_type) {
    // Exclude lowercase-starting names (invalid type names like object)
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
/// Check if type name is in exclusion list
fn is_excluded_type(name : String, exclude : Array[String]) -> Bool {
  exclude.contains(name)
}

///|
/// Output external type (only if not in exclusion list)
/// Returns whether the type was output
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
/// Generate file header (can specify types to exclude)
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

  // Output external types by category (only output header if types exist)
  ignore(
    external_header_types
    .iter()
    .fold(
      init=("", false), // (current_category, header_written)
      fn(state, entry) {
        let (current_category, header_written) = state
        let (type_name, category, comment) = entry
        if category != current_category {
          // Entered new category
          if not(is_excluded_type(type_name, exclude)) {
            // Output header if type will be output
            if current_category != "" {
              result.write_string("\n")
            }
            result.write_string("// ")
            result.write_string(category)
            result.write_string("\n")
            ignore(write_external_type(result, type_name, exclude, comment))
            (category, true)
          } else {
            // Don't output header if type is excluded
            (category, false)
          }
          // Within same category
        } else if not(header_written) &&
          not(is_excluded_type(type_name, exclude)) {
          // First type to output in this category, so output header
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
/// Generate file header (for backward compatibility)
pub fn gen_file_header(source_file : String) -> String {
  gen_file_header_with_exclude(source_file, [])
}

///|
/// Generate section separator comment
pub fn gen_section_comment(title : String) -> String {
  let result = StringBuilder::new()
  result.write_string("// ")
  // Create separator line matching title width
  let line_len = 60
  let title_len = title.length()
  let padding = (line_len - title_len - 4) / 2
  // Write padding characters
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
/// Format multiple definitions together
pub fn format_definitions(
  source_file : String,
  definitions : Array[Definition],
) -> String {
  let result = StringBuilder::new()

  // Collect type names defined in WebIDL (to avoid duplicate definitions)
  let defined_types = collect_defined_types(definitions)

  // Collect Dictionary type names (used in Union is_*/as_*)
  let dictionary_names : Array[String] = definitions
    .iter()
    .filter_map(fn(def) {
      match def {
        Dictionary(d) => Some(d.name)
        _ => None
      }
    })
    .collect()

  // File header (exclude types defined in WebIDL)
  result.write_string(gen_file_header_with_exclude(source_file, defined_types))

  // Declare undefined external types
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

  // Create enum map (used for enum argument string conversion)
  let enum_map : Array[(String, Array[String])] = []
  // Create enum name list (instanceof -> typeof === 'string')
  let enum_names : Array[String] = []
  // Create Union type set (used for .to_js_value() calls in to_js)
  let union_set : Array[String] = []
  // Create Union typedef map (used for type checking in is_*/as_*)
  let union_typedef_map : Array[(String, Array[IdlType])] = []
  // Create primitive typedef map (instanceof -> typeof check)
  let primitive_typedef_map : Array[(String, IdlType)] = []
  // Create callback interface name list (instanceof -> typeof === 'function')
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

  // Collect inline Unions
  let inline_unions = collect_inline_unions(definitions)
  // Add inline Union names to union_set
  inline_unions
  .iter()
  .filter(fn(entry) { not(union_set.contains(entry.0)) })
  .each(fn(entry) { union_set.push(entry.0) })

  // Types section (enum, dictionary, typedef, callback interface, inline unions)
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

    // Output Typedef first (may be referenced by other types)
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

    // Output inline Union typedef
    inline_unions
    .iter()
    .each(fn(entry) {
      let (name, members) = entry
      // Create TypedefDef to reuse gen_typedef
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

    // Output Enum
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

    // Output CallbackInterface (opaque type + from_fn helper)
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
          // Generate from_fn helper (only if has arguments)
          if cb.arguments.length() > 0 {
            result.write_string(gen_callback_from_fn(cb))
          }
        }
        _ => ()
      }
    })

    // Output Dictionary
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

  // Interfaces section
  // First build interfaces array (used for upcast/downcast method generation)
  let interfaces : Array[(String, InterfaceDef)] = definitions
    .iter()
    .filter_map(fn(def) {
      match def {
        Interface(iface) => Some((iface.name, iface))
        _ => None
      }
    })
    .collect()

  // Build inheritance map (used for downcast method generation)
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
/// Format single interface (with header)
/// Note: enum argument string conversion not performed (no enum map)
pub fn format_interface(source_file : String, iface : InterfaceDef) -> String {
  let result = StringBuilder::new()
  result.write_string(gen_file_header(source_file))
  let empty_enum_map : Array[(String, Array[String])] = []
  result.write_string(gen_interface_binding(iface, empty_enum_map))
  result.to_string()
}

///|
/// Normalize consecutive blank lines to one
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

  // Process last line
  let last_line = final_line.to_string()
  if not(is_blank_line(last_line)) {
    result.write_string(last_line)
  }
  result.to_string()
}

///|
/// Determine if line is blank
fn is_blank_line(line : String) -> Bool {
  line.iter().all(fn(c) { c == ' ' || c == '\t' })
}

///|
/// Normalize indent (convert tabs to two spaces)
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
/// Apply all formatting processes
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
/// Generate shared type definitions (for per-spec mode)
/// dictionary_names: Dictionary type name list (used in Union is_*/as_*)
/// union_typedef_map: Map from Union typedef name to constituent types
/// enum_names: enum type name list (instanceof -> typeof === 'string')
/// primitive_typedef_map: Map from primitive typedef name to resolved type
/// callback_interface_names: callback interface type name list (instanceof -> typeof === 'function')
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
    result.write_string("  #| () => (typeof window !== 'undefined') ? ")
    result.write_string(js_some("window"))
    result.write_string(" : ")
    result.write_string(js_none())
    result.write_string("\n\n")
  }
  result.to_string()
}

///|
/// Format output per spec (without external type declarations)
/// dictionary_names: Dictionary type name list (used in Union is_*/as_*)
/// union_typedef_map: Map from Union typedef name to constituent types
/// enum_names: enum type name list (instanceof -> typeof === 'string')
/// primitive_typedef_map: Map from primitive typedef name to resolved type
/// callback_interface_names: callback interface type name list (instanceof -> typeof === 'function')
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

  // Types section (typedef, enum, callback interface, dictionary)
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
    // Output Typedef first
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

    // Output Enum
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

    // Output CallbackInterface (opaque type + from_fn helper)
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
          // Generate from_fn helper (only if has arguments)
          if cb.arguments.length() > 0 {
            result.write_string(gen_callback_from_fn(cb))
          }
        }
        _ => ()
      }
    })

    // Output Dictionary
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

  // Interfaces section
  // Extract interfaces from this spec
  let spec_interfaces : Array[(String, InterfaceDef)] = definitions
    .iter()
    .filter_map(fn(def) {
      match def {
        Interface(iface) => Some((iface.name, iface))
        _ => None
      }
    })
    .collect()

  // Use global interfaces and inheritance_map (supports cross-spec inheritance)
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
/// Generate from_fn helper for callback interface
/// Example: pub extern "js" fn EventListener::from_fn(handler : (Event) -> Unit) -> EventListener
fn gen_callback_from_fn(cb : CallbackInterfaceDef) -> String {
  let result = StringBuilder::new()

  // Doc comment
  result.write_string("/// Create ")
  result.write_string(cb.name)
  result.write_string(" from a MoonBit function\n")

  // Function signature
  result.write_string("pub extern \"js\" fn ")
  result.write_string(cb.name)
  result.write_string("::from_fn(handler : (")

  // Argument type list
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

  // Return type
  result.write_string(") -> ")
  match cb.return_type {
    Some(Void) | None => result.write_string("Unit")
    Some(t) => result.write_string(idl_type_to_moonbit(t))
  }

  // Function return value (Callback type)
  result.write_string(") -> ")
  result.write_string(cb.name)
  result.write_string(" =\n")

  // JS implementation: wrap MoonBit closure in a proper JS function
  // MoonBit closures don't have Function.prototype.call/apply,
  // which some DOM APIs (e.g., addEventListener in happy-dom) require.
  result.write_string("  #| (handler) => (")
  // Generate JS parameter names (a0, a1, ...)
  let arg_count = cb.arguments.length()
  for i = 0; i < arg_count; i = i + 1 {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string("a")
    result.write_string(i.to_string())
  }
  result.write_string(") => handler(")
  for i = 0; i < arg_count; i = i + 1 {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string("a")
    result.write_string(i.to_string())
  }
  result.write_string(")\n\n")
  result.to_string()
}
