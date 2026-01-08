// Shared JS function generation for reducing code duplication
// This module generates shared JS functions for base interfaces
// and method wrappers for derived types

///|
/// Known base interfaces that will have shared JS functions generated
let base_interface_names : Array[String] = [
  "EventTarget",
  "Node",
  "Element",
  "HTMLElement",
  "SVGElement",
  "CharacterData",
  "Text",
  "Document",
  "DocumentFragment",
]

///|
/// Check if an interface is a known base interface
pub fn is_base_interface(name : String) -> Bool {
  for base in base_interface_names {
    if base == name {
      return true
    }
  }
  false
}

///|
/// Get the inheritance chain for an interface (from child to ancestors)
/// Returns list of parent names (not including self)
pub fn get_inheritance_chain(
  iface : InterfaceDef,
  all_interfaces : Array[(String, InterfaceDef)],
) -> Array[String] {
  let chain : Array[String] = []
  let mut current_inheritance = iface.inheritance

  while true {
    match current_inheritance {
      Some(parent_name) => {
        chain.push(parent_name)
        // Find parent interface
        let mut found = false
        for entry in all_interfaces {
          if entry.0 == parent_name {
            current_inheritance = entry.1.inheritance
            found = true
            break
          }
        }
        if not(found) {
          break
        }
      }
      None => break
    }
  }
  chain
}

///|
/// Collect base interfaces from definitions
pub fn collect_base_interfaces(
  definitions : Array[Definition],
) -> Array[(String, InterfaceDef)] {
  let result : Array[(String, InterfaceDef)] = []
  for def in definitions {
    match def {
      Interface(iface) => {
        if is_base_interface(iface.name) {
          result.push((iface.name, iface))
        }
      }
      _ => ()
    }
  }
  result
}

///|
/// Generate shared JS functions for all base interfaces
/// These functions will be called by method wrappers on derived types
pub fn gen_shared_js_functions(
  base_interfaces : Array[(String, InterfaceDef)],
) -> String {
  let result = StringBuilder::new()

  result.write_string("// ========================================\n")
  result.write_string("// Shared JS functions for inheritance\n")
  result.write_string("// ========================================\n\n")

  for entry in base_interfaces {
    let (name, iface) = entry
    result.write_string("// ----- ")
    result.write_string(name)
    result.write_string(" -----\n\n")

    for mem in iface.members {
      match mem {
        Operation(op) => {
          if op.name != "" {
            result.write_string(gen_shared_js_operation(name, op))
          }
        }
        Attribute(attr) => {
          result.write_string(gen_shared_js_getter(name, attr))
          if not(attr.is_readonly) {
            result.write_string(gen_shared_js_setter(name, attr))
          }
        }
        _ => ()
      }
    }
  }

  result.to_string()
}

///|
/// Generate a shared JS function for an operation
fn gen_shared_js_operation(
  interface_name : String,
  op : OperationDef,
) -> String {
  let result = StringBuilder::new()
  let fn_name = "js_" + to_snake_case(interface_name) + "_" + to_snake_case(op.name)

  result.write_string("///|\npub extern \"js\" fn ")
  result.write_string(fn_name)
  result.write_string("(target : JsValue")

  // Parameters
  for arg in op.arguments {
    result.write_string(", ")
    result.write_string(escape_reserved(to_snake_case(arg.name)))
    result.write_string(" : ")
    result.write_string(idl_type_to_moonbit(arg.idl_type))
  }

  result.write_string(") -> ")
  result.write_string(idl_type_to_moonbit(op.return_type))
  result.write_string(" =\n  #| (target")

  for arg in op.arguments {
    result.write_string(", ")
    result.write_string(to_snake_case(arg.name))
  }

  result.write_string(") => target.")
  result.write_string(op.name)
  result.write_string("(")

  let mut first = true
  for arg in op.arguments {
    if not(first) {
      result.write_string(", ")
    }
    first = false
    result.write_string(to_snake_case(arg.name))
  }

  result.write_string(")\n\n")
  result.to_string()
}

///|
/// Generate a shared JS getter
fn gen_shared_js_getter(
  interface_name : String,
  attr : AttributeDef,
) -> String {
  let result = StringBuilder::new()
  let fn_name = "js_" + to_snake_case(interface_name) + "_get_" + to_snake_case(attr.name)

  result.write_string("///|\npub extern \"js\" fn ")
  result.write_string(fn_name)
  result.write_string("(target : JsValue) -> ")
  result.write_string(idl_type_to_moonbit(attr.idl_type))
  result.write_string(" =\n  #| (target) => target.")
  result.write_string(attr.name)
  result.write_string("\n\n")

  result.to_string()
}

///|
/// Generate a shared JS setter
fn gen_shared_js_setter(
  interface_name : String,
  attr : AttributeDef,
) -> String {
  let result = StringBuilder::new()
  let fn_name = "js_" + to_snake_case(interface_name) + "_set_" + to_snake_case(attr.name)

  result.write_string("///|\npub extern \"js\" fn ")
  result.write_string(fn_name)
  result.write_string("(target : JsValue, value : ")
  result.write_string(idl_type_to_moonbit(attr.idl_type))
  result.write_string(") -> Unit =\n  #| (target, value) => { target.")
  result.write_string(attr.name)
  result.write_string(" = value }\n\n")

  result.to_string()
}

///|
/// Generate method wrappers for inherited members
/// These wrappers call the shared JS functions
/// Tracks generated methods to avoid duplicates when inheriting from multiple bases
pub fn gen_inherited_method_wrappers(
  type_name : String,
  base_interface_name : String,
  members : Array[InterfaceMember],
  generated_methods : Array[String],
) -> String {
  let result = StringBuilder::new()
  let prefix = "js_" + to_snake_case(base_interface_name) + "_"

  for mem in members {
    match mem {
      Operation(op) => {
        if op.name != "" {
          let method_name = to_snake_case(op.name)
          let mut already_gen = false
          for m in generated_methods {
            if m == method_name {
              already_gen = true
              break
            }
          }
          if not(already_gen) {
            generated_methods.push(method_name)
            result.write_string(gen_method_wrapper(type_name, prefix, op))
          }
        }
      }
      Attribute(attr) => {
        let getter_name = "get_" + to_snake_case(attr.name)
        let mut getter_gen = false
        for m in generated_methods {
          if m == getter_name {
            getter_gen = true
            break
          }
        }
        if not(getter_gen) {
          generated_methods.push(getter_name)
          result.write_string(gen_getter_wrapper(type_name, prefix, attr))
        }
        if not(attr.is_readonly) {
          let setter_name = "set_" + to_snake_case(attr.name)
          let mut setter_gen = false
          for m in generated_methods {
            if m == setter_name {
              setter_gen = true
              break
            }
          }
          if not(setter_gen) {
            generated_methods.push(setter_name)
            result.write_string(gen_setter_wrapper(type_name, prefix, attr))
          }
        }
      }
      _ => ()
    }
  }

  result.to_string()
}

///|
/// Generate a method wrapper
fn gen_method_wrapper(
  type_name : String,
  fn_prefix : String,
  op : OperationDef,
) -> String {
  let result = StringBuilder::new()
  let snake_name = to_snake_case(op.name)

  result.write_string("pub fn ")
  result.write_string(type_name)
  result.write_string("::")
  result.write_string(escape_reserved(snake_name))
  result.write_string("(self : ")
  result.write_string(type_name)

  for arg in op.arguments {
    result.write_string(", ")
    result.write_string(escape_reserved(to_snake_case(arg.name)))
    result.write_string(" : ")
    result.write_string(idl_type_to_moonbit(arg.idl_type))
  }

  result.write_string(") -> ")
  result.write_string(idl_type_to_moonbit(op.return_type))
  result.write_string(" {\n  ")
  result.write_string(fn_prefix)
  result.write_string(snake_name)
  result.write_string("(self.to_js_value()")

  for arg in op.arguments {
    result.write_string(", ")
    result.write_string(escape_reserved(to_snake_case(arg.name)))
  }

  result.write_string(")\n}\n\n")
  result.to_string()
}

///|
/// Generate a getter wrapper
fn gen_getter_wrapper(
  type_name : String,
  fn_prefix : String,
  attr : AttributeDef,
) -> String {
  let result = StringBuilder::new()
  let snake_name = to_snake_case(attr.name)

  result.write_string("pub fn ")
  result.write_string(type_name)
  result.write_string("::get_")
  result.write_string(escape_reserved(snake_name))
  result.write_string("(self : ")
  result.write_string(type_name)
  result.write_string(") -> ")
  result.write_string(idl_type_to_moonbit(attr.idl_type))
  result.write_string(" {\n  ")
  result.write_string(fn_prefix)
  result.write_string("get_")
  result.write_string(snake_name)
  result.write_string("(self.to_js_value())\n}\n\n")

  result.to_string()
}

///|
/// Generate a setter wrapper
fn gen_setter_wrapper(
  type_name : String,
  fn_prefix : String,
  attr : AttributeDef,
) -> String {
  let result = StringBuilder::new()
  let snake_name = to_snake_case(attr.name)

  result.write_string("pub fn ")
  result.write_string(type_name)
  result.write_string("::set_")
  result.write_string(escape_reserved(snake_name))
  result.write_string("(self : ")
  result.write_string(type_name)
  result.write_string(", value : ")
  result.write_string(idl_type_to_moonbit(attr.idl_type))
  result.write_string(") -> Unit {\n  ")
  result.write_string(fn_prefix)
  result.write_string("set_")
  result.write_string(snake_name)
  result.write_string("(self.to_js_value(), value)\n}\n\n")

  result.to_string()
}
