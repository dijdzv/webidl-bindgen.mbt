// MDN-based throws map builder.
// Fetches MDN content pages and parses ### Exceptions sections
// to detect which methods/constructors/attributes throw.

///|
/// Build includes map: mixin_name → first target interface name.
/// Used to resolve mixin member MDN URLs (MDN uses target interface, not mixin name).
fn build_includes_map(
  definitions : Array[Definition],
) -> Array[(String, String)] {
  let map : Array[(String, String)] = []
  for def in definitions {
    match def {
      Includes(inc) => {
        // Only record first mapping for each mixin
        let exists = map.iter().any(fn(e) { e.0 == inc.includes })
        if !exists {
          map.push((inc.includes, inc.target))
        }
      }
      _ => ()
    }
  }
  map
}

///|
/// Look up target interface for a mixin name.
fn resolve_mixin(
  includes_map : Array[(String, String)],
  mixin_name : String,
) -> String? {
  for entry in includes_map {
    if entry.0 == mixin_name {
      return Some(entry.1)
    }
  }
  None
}

///|
/// Entry for MDN lookup: (iface_for_url, iface_for_key, member_name, entry_type)
/// - iface_for_url: interface name for MDN URL (mixin resolved to target)
/// - iface_for_key: interface name for ThrowsMap key (mixin name as-is)
/// - member_name: method/attribute/constructor name
/// - entry_type: "method" | "static_method" | "constructor" | "attribute"
struct MdnLookupEntry {
  iface_for_url : String
  iface_for_key : String
  member_name : String
  entry_type : String
}

///|
/// Collect all members that need MDN lookup.
fn collect_lookup_entries(
  definitions : Array[Definition],
  includes_map : Array[(String, String)],
) -> Array[MdnLookupEntry] {
  let entries : Array[MdnLookupEntry] = []
  for def in definitions {
    let (iface_name, members, is_mixin) = match def {
      Interface(iface) => (iface.name, iface.members, false)
      InterfaceMixin(mix) => (mix.name, mix.members, true)
      Namespace(ns) => (ns.name, ns.members, false)
      Partial(partial) => (partial.target, partial.members, false)
      _ => continue
    }
    let iface_for_url = if is_mixin {
      match resolve_mixin(includes_map, iface_name) {
        Some(target) => target
        None => continue // mixin with no known target
      }
    } else {
      iface_name
    }
    for m in members {
      match m {
        Operation(op) => {
          if op.name.is_empty() {
            continue
          }
          let entry_type = if op.special is Some("static") {
            "static_method"
          } else {
            "method"
          }
          entries.push({
            iface_for_url,
            iface_for_key: iface_name,
            member_name: op.name,
            entry_type,
          })
        }
        Constructor(_) =>
          entries.push({
            iface_for_url,
            iface_for_key: iface_name,
            member_name: "constructor",
            entry_type: "constructor",
          })
        Attribute(attr) => {
          if attr.is_readonly {
            continue
          }
          entries.push({
            iface_for_url,
            iface_for_key: iface_name,
            member_name: attr.name,
            entry_type: "attribute",
          })
        }
        _ => ()
      }
    }
  }
  entries
}

///|
/// Build MDN raw content URL for a member.
fn mdn_url(iface : String, name : String, entry_type : String) -> String {
  let base = "https://raw.githubusercontent.com/mdn/content/main/files/en-us/web/api/"
  let iface_lower = to_lower_case(iface)
  let member_lower = if entry_type == "constructor" {
    iface_lower
  } else if entry_type == "static_method" {
    to_lower_case(name) + "_static"
  } else {
    to_lower_case(name)
  }
  base + iface_lower + "/" + member_lower + "/index.md"
}

///|
/// Deduplicate entries by (iface_for_url, member_name, entry_type).
/// Keeps the first occurrence for each unique key.
fn dedup_entries(entries : Array[MdnLookupEntry]) -> Array[MdnLookupEntry] {
  let seen : Array[String] = []
  let result : Array[MdnLookupEntry] = []
  for e in entries {
    let key = e.iface_for_url + "." + e.member_name + "." + e.entry_type
    if !seen.contains(key) {
      seen.push(key)
      result.push(e)
    }
  }
  result
}

///|
fn format_entry_label(entry : MdnLookupEntry) -> String {
  match entry.entry_type {
    "constructor" => entry.iface_for_url + ".constructor"
    "attribute" => entry.iface_for_url + "." + entry.member_name + " (setter)"
    "static_method" =>
      entry.iface_for_url + "." + entry.member_name + " (static)"
    _ => entry.iface_for_url + "." + entry.member_name
  }
}

///|
pub struct MdnThrowsResult {
  throws_map : ThrowsMap
  total_fetched : Int
  not_found : Int
  not_found_entries : Array[String] // "Interface.member" entries with 404
  has_section_but_no_parse : Int // pages with ### Exceptions but no exceptions extracted
  has_section_but_no_parse_entries : Array[String]
}

///|
/// Generate a markdown report of MDN throws diagnostics.
pub fn gen_not_found_report(result : MdnThrowsResult) -> String {
  let sb = StringBuilder::new()
  sb.write_string("# MDN Throws: Diagnostic Report\n\n")
  sb.write_string(
    "Detected " +
    throws_map_size(result.throws_map).to_string() +
    " throwing members from MDN.\n\n",
  )
  // 404 section
  if result.not_found > 0 {
    sb.write_string("## Not Found (404)\n\n")
    sb.write_string(
      result.not_found.to_string() +
      " / " +
      result.total_fetched.to_string() +
      " MDN pages were not found.\n",
    )
    sb.write_string(
      "These members may throw but have no MDN documentation page.\n\n",
    )
    for entry in result.not_found_entries {
      sb.write_string("- " + entry + "\n")
    }
    sb.write_string("\n")
  }
  // Parse failure section
  if result.has_section_but_no_parse > 0 {
    sb.write_string("## Exceptions Section Found But Not Parsed\n\n")
    sb.write_string(
      result.has_section_but_no_parse.to_string() +
      " pages have an `### Exceptions` section but no exception names were extracted.\n",
    )
    sb.write_string(
      "This may indicate an unrecognized MDN format that the parser should handle.\n\n",
    )
    for entry in result.has_section_but_no_parse_entries {
      sb.write_string("- " + entry + "\n")
    }
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
/// Main pipeline: build ThrowsMap from MDN content.
pub async fn build_throws_map_from_mdn(
  definitions : Array[Definition],
) -> MdnThrowsResult {
  let map = create_throws_map()
  let empty = {
    throws_map: map,
    total_fetched: 0,
    not_found: 0,
    not_found_entries: [],
    has_section_but_no_parse: 0,
    has_section_but_no_parse_entries: [],
  }
  // 1. Build includes map for mixin resolution
  let includes_map = build_includes_map(definitions)
  // 2. Collect all lookup entries
  let raw_entries = collect_lookup_entries(definitions, includes_map)
  let entries = dedup_entries(raw_entries)
  if entries.length() == 0 {
    return empty
  }
  // 3. Build URL array and fetch
  let urls = create_js_string_array()
  for e in entries {
    push_js_string_array(
      urls,
      mdn_url(e.iface_for_url, e.member_name, e.entry_type),
    )
  }
  let results = batch_fetch_mdn_promise(urls).wait()
  let count = mdn_results_count(results)
  // 4. Parse exceptions from each result, track 404s and parse failures
  let not_found_entries : Array[String] = []
  let has_section_but_no_parse_entries : Array[String] = []
  for i = 0; i < count; i = i + 1 {
    let content = mdn_result_content(results, i)
    if content == "" {
      let entry = entries[i]
      not_found_entries.push(format_entry_label(entry))
      continue
    }
    let exceptions_arr = parse_mdn_exceptions_js(content)
    let exceptions = js_array_to_strings(exceptions_arr)
    if exceptions.length() == 0 {
      // Page exists but no exceptions parsed — check if section exists
      if has_exceptions_section(content) {
        let entry = entries[i]
        has_section_but_no_parse_entries.push(format_entry_label(entry))
      }
      continue
    }
    let entry = entries[i]
    if entry.entry_type == "attribute" {
      set_attribute_throws(
        map,
        entry.iface_for_key,
        entry.member_name,
        exceptions,
      )
    } else if entry.entry_type == "constructor" {
      set_throws(map, entry.iface_for_key, "constructor", exceptions)
    } else {
      set_throws(map, entry.iface_for_key, entry.member_name, exceptions)
    }
  }
  {
    throws_map: map,
    total_fetched: count,
    not_found: not_found_entries.length(),
    not_found_entries,
    has_section_but_no_parse: has_section_but_no_parse_entries.length(),
    has_section_but_no_parse_entries,
  }
}

///|
/// Built-in throws overrides. Edit here to add/remove entries MDN doesn't detect.
let builtin_throws_overrides : String =
  #|{"add":{"Animation.finish":["InvalidStateError"]},"remove":[]}

///|
/// Apply built-in overrides to the ThrowsMap.
pub fn apply_throws_overrides(map : ThrowsMap) -> (Int, Int) {
  let packed = apply_throws_overrides_js(map, builtin_throws_overrides)
  (packed / 1000, packed % 1000)
}
