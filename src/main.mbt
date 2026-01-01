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
extern "js" fn read_file_sync(path : String) -> String =
  #| (path) => require('fs').readFileSync(path, 'utf-8')

///|
extern "js" fn write_file_sync(path : String, content : String) -> Unit =
  #| (path, content) => require('fs').writeFileSync(path, content, 'utf-8')

///|
extern "js" fn mkdir_sync(path : String) -> Unit =
  #| (path) => require('fs').mkdirSync(path, { recursive: true })

///|
extern "js" fn path_join(a : String, b : String) -> String =
  #| (a, b) => require('path').join(a, b)

///|
extern "js" fn path_basename(p : String, ext : String) -> String =
  #| (p, ext) => require('path').basename(p, ext)

///|
extern "js" fn exit_process(code : Int) -> Unit =
  #| (code) => process.exit(code)

// CLI argument structure

///|
struct CliArgs {
  input : String
  spec : String
  specs : String // comma-separated list of specs
  all : Bool // load all specs
  per_spec : Bool // output each spec to separate file
  output : String
  help : Bool
}

///|
fn parse_args() -> CliArgs {
  let argc = get_argv_length()
  let mut input = ""
  let mut spec = ""
  let mut specs = ""
  let mut all = false
  let mut per_spec = false
  let mut output = "./"
  let mut help = false
  let mut i = 2 // Skip node and script path
  while i < argc {
    let arg = get_argv_string(i)
    if arg == "--help" || arg == "-h" {
      help = true
    } else if arg == "--input" || arg == "-i" {
      i = i + 1
      if i < argc {
        input = get_argv_string(i)
      }
    } else if arg == "--spec" || arg == "-s" {
      i = i + 1
      if i < argc {
        spec = get_argv_string(i)
      }
    } else if arg == "--specs" {
      i = i + 1
      if i < argc {
        specs = get_argv_string(i)
      }
    } else if arg == "--all" || arg == "-a" {
      all = true
    } else if arg == "--per-spec" {
      per_spec = true
    } else if arg == "--output" || arg == "-o" {
      i = i + 1
      if i < argc {
        output = get_argv_string(i)
      }
    } else if input == "" && not(starts_with(arg, "--")) {
      // Positional argument as input
      input = arg
    }
    i = i + 1
  }
  { input, spec, specs, all, per_spec, output, help }
}

///|
fn print_usage() -> Unit {
  println("webidl-bindgen: WebIDL to MoonBit binding generator")
  println("")
  println("Usage:")
  println("  webidl-bindgen [options] <input.webidl>")
  println("")
  println("Options:")
  println("  -i, --input <file>      Input WebIDL file")
  println("  -s, --spec <name>       Single spec from @webref/idl (e.g., html)")
  println("      --specs <list>      Comma-separated list of specs")
  println("  -a, --all               Load all specs from @webref/idl")
  println(
    "      --per-spec          Output each spec to separate file (with --all or --specs)",
  )
  println("  -o, --output <dir>      Output directory (default: ./)")
  println("  -h, --help              Show this help message")
  println("")
  println("Note: --input, --spec, --specs, and --all are mutually exclusive")
  println("")
  println("Examples:")
  println("  webidl-bindgen -i canvas2d.webidl -o ./src/")
  println("  webidl-bindgen --spec html -o ./src/")
  println("  webidl-bindgen --specs html,dom,cssom -o ./src/")
  println("  webidl-bindgen --all -o ./src/")
  println(
    "  webidl-bindgen --all --per-spec -o ./src/  # Output each spec separately",
  )
}

///|
fn starts_with(s : String, prefix : String) -> Bool {
  let mut prefix_len = 0
  for _ in prefix {
    prefix_len = prefix_len + 1
  }
  let mut s_len = 0
  for _ in s {
    s_len = s_len + 1
  }
  if prefix_len > s_len {
    return false
  }

  // Compare character by character
  let mut matched = true
  let mut idx = 0
  for c in s {
    if idx >= prefix_len {
      break
    }
    let mut prefix_idx = 0
    for pc in prefix {
      if prefix_idx == idx {
        if c != pc {
          matched = false
          break
        }
        break
      }
      prefix_idx = prefix_idx + 1
    }
    if not(matched) {
      break
    }
    idx = idx + 1
  }
  matched
}

///|
/// カンマ区切り文字列を配列に分割
fn split_by_comma(s : String) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  for c in s {
    if c == ',' {
      let trimmed = current.to_string()
      if trimmed != "" {
        result.push(trimmed)
      }
      current.reset()
    } else if c != ' ' {
      current.write_char(c)
    }
  }

  // Add last segment
  let trimmed = current.to_string()
  if trimmed != "" {
    result.push(trimmed)
  }
  result
}

///|
async fn main {
  let args = parse_args()
  if args.help {
    print_usage()
    return
  }

  // Count how many source modes are specified
  let mut mode_count = 0
  if args.input != "" {
    mode_count = mode_count + 1
  }
  if args.spec != "" {
    mode_count = mode_count + 1
  }
  if args.specs != "" {
    mode_count = mode_count + 1
  }
  if args.all {
    mode_count = mode_count + 1
  }
  if mode_count > 1 {
    println("Error: --input, --spec, --specs, and --all are mutually exclusive")
    println("")
    print_usage()
    exit_process(1)
    return
  }
  if mode_count == 0 {
    println(
      "Error: One of --input, --spec, --specs, or --all must be specified",
    )
    println("")
    print_usage()
    exit_process(1)
    return
  }

  // Create output directory
  mkdir_sync(args.output)

  // Handle multi-spec modes (--specs or --all)
  if args.specs != "" || args.all {
    let webref_specs = list_all_specs()
    let spec_names = if args.all {
      println("Loading all specs from @webref/idl...")
      get_all_spec_names(webref_specs)
    } else {
      split_by_comma(args.specs)
    }
    println("Processing " + spec_names.length().to_string() + " specs...")

    // Load all specs
    let results = load_multiple_specs(webref_specs, spec_names, true)

    // Report errors
    let mut error_count = 0
    for result in results {
      if not(result.success) {
        println("Warning: " + result.error_message)
        error_count = error_count + 1
      }
    }

    // Per-spec mode: output each spec to separate file
    if args.per_spec {
      println("Generating per-spec MoonBit files...")

      // Build global type ownership map (first definition wins)
      println("Building type ownership map...")
      let ownership = build_global_type_ownership(results)
      println("Registered " + ownership.length().to_string() + " unique types")

      // Collect all definitions to find external types
      let all_definitions = merge_all_results(results)

      // Collect external types (referenced but not defined)
      println("Collecting external types...")
      let external_types = collect_external_types_with_ownership(
        all_definitions, ownership,
      )
      println(
        "Found " + external_types.length().to_string() + " external types",
      )

      // Build global enum map (for enum argument string conversion)
      let global_enum_map : Array[(String, Array[String])] = []
      for def in all_definitions {
        match def {
          Enum(e) => global_enum_map.push((e.name, e.values))
          _ => ()
        }
      }

      // Write shared.mbt with common types and external declarations
      let shared_code = gen_shared_types_with_externals(external_types)
      let shared_file = path_join(args.output, "shared.js.mbt")
      println("Writing: " + shared_file)
      write_file_sync(shared_file, shared_code)

      // Count successful specs
      let mut success_count = 0
      let mut total_defs = 0

      // Collect all definitions from all specs (for cross-spec partial interface merging)
      let all_definitions = merge_all_results(results)

      // Output each spec to its own file
      for result in results {
        if result.success && result.definitions.length() > 0 {
          // Filter ALL definitions (from all specs) to only include those owned by this spec
          // This ensures partial interfaces from other specs are included
          let owned_defs = filter_definitions_by_owner(
            all_definitions,
            result.spec_name,
            ownership,
          )
          // Only write file if there are owned definitions
          if owned_defs.length() > 0 {
            let merged = merge_definitions(owned_defs)
            let code = format_spec_output(
              result.spec_name,
              merged,
              global_enum_map,
            )
            let output_file = path_join(
              args.output,
              result.spec_name + ".js.mbt",
            )
            write_file_sync(output_file, code)
            success_count = success_count + 1
            total_defs = total_defs + merged.length()
          }
        }
      }
      println(
        "Done! Generated " +
        success_count.to_string() +
        " files with " +
        total_defs.to_string() +
        " total definitions",
      )
      return
    }

    // Single file mode: merge all definitions
    let all_definitions = merge_all_results(results)
    println(
      "Total definitions: " +
      all_definitions.length().to_string() +
      " (from " +
      (results.length() - error_count).to_string() +
      " specs)",
    )

    // Generate output
    println("Generating MoonBit code...")
    let source_name = if args.all {
      "@webref/idl (all specs)"
    } else {
      "@webref/idl (" + args.specs + ")"
    }
    let output_code = format_output(source_name, all_definitions)

    // Write output file
    let basename = if args.all { "web-sys" } else { "bindings" }
    let output_file = path_join(args.output, basename + ".js.mbt")
    println("Writing: " + output_file)
    write_file_sync(output_file, output_code)
    if error_count > 0 {
      println("Done with " + error_count.to_string() + " warnings (see above)")
    } else {
      println("Done!")
    }
    return
  }

  // Single spec or file mode
  let (source, source_file, basename) = if args.spec != "" {
    // --spec mode: fetch WebIDL from @webref/idl
    println("Fetching spec: " + args.spec)
    let specs = list_all_specs()
    if not(spec_exists(specs, args.spec)) {
      println("Error: Spec '" + args.spec + "' not found in @webref/idl")
      exit_process(1)
      return
    }
    let idl_text = get_idl_by_name(specs, args.spec)
    if idl_text == "" {
      println("Error: Failed to fetch WebIDL for spec '" + args.spec + "'")
      exit_process(1)
      return
    }
    println("Loaded WebIDL from @webref/idl/" + args.spec)
    (idl_text, "@webref/idl/" + args.spec, args.spec)
  } else {
    // --input mode: read from file
    println("Reading: " + args.input)
    let content = read_file_sync(args.input)
    (content, args.input, path_basename(args.input, ".webidl"))
  }

  // Parse WebIDL
  println("Parsing WebIDL...")
  let parse_result = parse_webidl_raw(source)
  if not(is_parse_success(parse_result)) {
    let error = get_parse_error(parse_result)
    println("Parse error: " + error)
    exit_process(1)
    return
  }

  // Convert to AST
  println("Converting to AST...")
  let definitions = convert_to_definitions(parse_result)

  // Generate output
  println("Generating MoonBit code...")
  let output_code = format_output(source_file, definitions)

  // Write output file
  let output_file = path_join(args.output, basename + ".js.mbt")
  println("Writing: " + output_file)
  write_file_sync(output_file, output_code)
  println("Done!")
}
