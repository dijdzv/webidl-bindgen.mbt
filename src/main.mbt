// WebIDL to MoonBit binding generator
// Entry point for CLI

// Node.js/Bun FFI for CLI - uses types from parser.mbt

///|
extern "js" fn get_argv_string(index : Int) -> String =
  #| (index) => process.argv[index]

///|
extern "js" fn get_argv_length() -> Int =
  #| () => process.argv.length

///|
extern "js" fn write_file_sync(path : String, content : String) -> Unit =
  #| (path, content) => require('fs').writeFileSync(path, content, 'utf-8')

///|
extern "js" fn mkdir_sync(path : String) -> Unit =
  #| (path) => require('fs').mkdirSync(path, { recursive: true })

///|
extern "js" fn path_join(a : String, b : String) -> String =
  #| (a, b) => require('path').join(a, b)

// CLI argument structure

///|
struct CliArgs {
  output : String
  help : Bool
}

///|
fn parse_args() -> CliArgs {
  let argc = get_argv_length()
  let mut output = "./"
  let mut help = false
  let mut i = 2 // Skip node and script path
  while i < argc {
    let arg = get_argv_string(i)
    if arg == "--help" || arg == "-h" {
      help = true
    } else if arg == "--output" || arg == "-o" {
      i = i + 1
      if i < argc {
        output = get_argv_string(i)
      }
    }
    i = i + 1
  }
  { output, help }
}

///|
fn print_usage() -> Unit {
  println("webidl-bindgen.mbt: WebIDL to MoonBit binding generator")
  println("")
  println("Usage:")
  println("  webidl-bindgen.mbt [options]")
  println("")
  println("Options:")
  println("  -o, --output <dir>  Output directory (default: ./)")
  println("  -h, --help          Show this help message")
}

///|
async fn main {
  let args = parse_args()
  if args.help {
    print_usage()
    return
  }

  // Create output directory
  mkdir_sync(args.output)

  // Load all specs from @webref/idl
  let webref_specs = list_all_specs()
  println("Loading all specs from @webref/idl...")
  let spec_names = get_all_spec_names(webref_specs)
  println("Processing " + spec_names.length().to_string() + " specs...")
  let results = load_multiple_specs(webref_specs, spec_names, true)

  // Report errors
  for result in results {
    if !result.success {
      println("Warning: " + result.error_message)
    }
  }

  // Build throws map from MDN
  println("Building throws map from MDN content...")
  let all_defs = merge_all_results(results)
  let mdn_result = build_throws_map_from_mdn(all_defs)
  let map_size = throws_map_size(mdn_result.throws_map)
  println(
    "Detected " +
    map_size.to_string() +
    " throwing members from MDN (" +
    mdn_result.not_found.to_string() +
    "/" +
    mdn_result.total_fetched.to_string() +
    " pages not found)",
  )
  if mdn_result.has_section_but_no_parse > 0 {
    println(
      "Warning: " +
      mdn_result.has_section_but_no_parse.to_string() +
      " pages have ### Exceptions section but no exceptions were parsed",
    )
  }
  // Apply built-in overrides
  let (added, removed) = apply_throws_overrides(mdn_result.throws_map)
  if added > 0 || removed > 0 {
    println(
      "Applied throws overrides: +" +
      added.to_string() +
      " added, -" +
      removed.to_string() +
      " removed",
    )
  }
  let final_size = throws_map_size(mdn_result.throws_map)
  if final_size > 0 {
    let throws_maps : Array[(String, ThrowsMap)] = [
      ("mdn", mdn_result.throws_map),
    ]
    for result in results {
      if result.success {
        inject_throws(result.definitions, throws_maps)
      }
    }
  }
  if mdn_result.not_found > 0 || mdn_result.has_section_but_no_parse > 0 {
    let report_file = path_join(args.output, "throws_not_found.md")
    write_file_sync(report_file, gen_not_found_report(mdn_result))
    println("Writing: " + report_file)
  }

  // Generate per-spec MoonBit files
  println("Generating per-spec MoonBit files...")

  // Build global type ownership map (first definition wins)
  let ownership = build_global_type_ownership(results)
  println("Registered " + ownership.length().to_string() + " unique types")

  // Collect all definitions
  let all_definitions = merge_all_results(results)

  // Collect external types (referenced but not defined)
  let external_types = collect_external_types_with_ownership(
    all_definitions, ownership,
  )
  println("Found " + external_types.length().to_string() + " external types")

  // Build global maps
  let global_enum_map : Array[(String, Array[String])] = []
  let global_union_set : Array[String] = []
  let dictionary_names : Array[String] = []
  let union_typedef_map : Array[(String, Array[IdlType])] = []
  let enum_names : Array[String] = []
  let primitive_typedef_map : Array[(String, IdlType)] = []
  let callback_interface_names : Array[String] = []
  let global_dict_map : Array[(String, DictionaryDef)] = []
  all_definitions
  .iter()
  .each(fn(def) {
    match def {
      Enum(e) => {
        global_enum_map.push((e.name, e.values))
        enum_names.push(e.name)
      }
      Typedef(t) =>
        match t.idl_type {
          Union(members) => {
            global_union_set.push(t.name)
            union_typedef_map.push((t.name, members))
          }
          other => primitive_typedef_map.push((t.name, other))
        }
      Dictionary(d) => {
        dictionary_names.push(d.name)
        global_dict_map.push((d.name, d))
      }
      CallbackInterface(cb) => callback_interface_names.push(cb.name)
      _ => ()
    }
  })

  // Collect inline Unions
  let inline_unions = collect_inline_unions(all_definitions)
  inline_unions
  .iter()
  .each(fn(entry) {
    let (name, _) = entry
    if !global_union_set.contains(name) {
      global_union_set.push(name)
    }
  })

  let defined_types = ownership.map(fn(entry) { entry.0 })

  // Build global interfaces list for inheritance map
  let global_interfaces : Array[(String, InterfaceDef)] = all_definitions
    .iter()
    .filter_map(fn(def) {
      match def {
        Interface(iface) => Some((iface.name, iface))
        _ => None
      }
    })
    .collect()
  let global_inheritance_map = build_inheritance_map(global_interfaces)

  // Write shared.mbt
  let shared_code = gen_shared_types_with_externals(
    external_types,
    inline_unions,
    defined_types,
    dictionary_names,
    union_typedef_map~,
    enum_names~,
    primitive_typedef_map~,
    callback_interface_names~,
  )
  let shared_file = path_join(args.output, "shared.mbt")
  println("Writing: " + shared_file)
  write_file_sync(shared_file, shared_code)

  // Output each spec to its own file
  let (success_count, total_defs) = results
    .iter()
    .fold(init=(0, 0), fn(counts, result) {
      let (success_count, total_defs) = counts
      if result.success && result.definitions.length() > 0 {
        let owned_defs = filter_definitions_by_owner(
          all_definitions,
          result.spec_name,
          ownership,
        )
        if owned_defs.length() > 0 {
          let merged = merge_definitions(owned_defs)
          let code = format_spec_output(
            result.spec_name,
            merged,
            global_enum_map,
            global_union_set,
            dictionary_names,
            union_typedef_map~,
            enum_names~,
            primitive_typedef_map~,
            callback_interface_names~,
            global_interfaces~,
            global_inheritance_map~,
            global_dict_map~,
          )
          if merged.length() > 0 {
            let output_file = path_join(args.output, result.spec_name + ".mbt")
            write_file_sync(output_file, code)
            (success_count + 1, total_defs + merged.length())
          } else {
            counts
          }
        } else {
          counts
        }
      } else {
        counts
      }
    })
  println(
    "Done! Generated " +
    success_count.to_string() +
    " files with " +
    total_defs.to_string() +
    " total definitions",
  )
}
