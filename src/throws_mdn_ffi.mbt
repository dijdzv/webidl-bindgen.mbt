// JS FFI for MDN-based throws detection: batch fetch and markdown parsing

///|
/// Batch fetch MDN raw content URLs with concurrency control.
/// Returns array of response bodies (404/error → empty string).
extern "js" fn batch_fetch_mdn_promise(
  urls : JsArray,
) -> @js_async.Promise[JsValue] =
  #| (urls) => {
  #|   const CONCURRENCY = 50;
  #|   const results = new Array(urls.length).fill('');
  #|   let idx = 0;
  #|   async function worker() {
  #|     while (idx < urls.length) {
  #|       const i = idx++;
  #|       try {
  #|         const r = await fetch(urls[i]);
  #|         if (r.ok) results[i] = await r.text();
  #|       } catch {}
  #|     }
  #|   }
  #|   const workers = [];
  #|   for (let w = 0; w < Math.min(CONCURRENCY, urls.length); w++) workers.push(worker());
  #|   return Promise.all(workers).then(() => results);
  #| }

///|
/// Get number of results from batch fetch
extern "js" fn mdn_results_count(data : JsValue) -> Int =
  #| (d) => d.length

///|
/// Get content of result at index
extern "js" fn mdn_result_content(data : JsValue, i : Int) -> String =
  #| (d, i) => d[i]

///|
/// Parse ### Exceptions section from MDN markdown.
/// Extracts exception names from patterns like:
///   - `ExceptionName` {{domxref("DOMException")}}
///   - {{jsxref("TypeError")}}
///   - {{jsxref("RangeError")}}
/// Returns array of exception name strings.
extern "js" fn parse_mdn_exceptions_js(markdown : String) -> JsArray =
  #| (md) => {
  #|   const excMatch = md.match(/^###?\s+Exceptions?\b/m);
  #|   if (!excMatch) return [];
  #|   const start = excMatch.index + excMatch[0].length;
  #|   const rest = md.slice(start);
  #|   const nextSection = rest.search(/^##\s/m);
  #|   const section = nextSection > 0 ? rest.slice(0, nextSection) : rest;
  #|   const names = new Set();
  #|   const re1 = /[`-]\s*`(\w+)`\s*\{\{domxref\("DOMException"\)\}\}/gi;
  #|   let m;
  #|   while ((m = re1.exec(section)) !== null) names.add(m[1]);
  #|   const re2 = /\{\{jsxref\(["'](\w+)["']\)\}\}/gi;
  #|   while ((m = re2.exec(section)) !== null) names.add(m[1]);
  #|   const re3 = /[`-]\s*`(\w+Error)`/g;
  #|   while ((m = re3.exec(section)) !== null) names.add(m[1]);
  #|   const re4 = /[`-]\s*\{\{domxref\("(\w+Error)"\)\}\}/gi;
  #|   while ((m = re4.exec(section)) !== null) names.add(m[1]);
  #|   const re5 = /\[`(\w+Error?)`\]\(\/en-US\/docs\//g;
  #|   while ((m = re5.exec(section)) !== null) names.add(m[1]);
  #|   const re6 = /\{\{domxref\("DOMException"\)\}\}\s+of\s+type\s+`(\w+)`/gi;
  #|   while ((m = re6.exec(section)) !== null) names.add(m[1]);
  #|   const re7 = /<code>(\w+(?:Error|Exception))<\/code>/gi;
  #|   while ((m = re7.exec(section)) !== null) names.add(m[1]);
  #|   return [...names];
  #| }

///|
/// Check if markdown has an ### Exceptions section with actual exception content.
/// Returns false for sections that only contain "None", GL error constants,
/// or prose that doesn't list specific JS exceptions.
extern "js" fn has_exceptions_section(markdown : String) -> Bool =
  #| (md) => {
  #|   const excMatch = md.match(/^###?\s+Exceptions?\b/m);
  #|   if (!excMatch) return false;
  #|   const start = excMatch.index + excMatch[0].length;
  #|   const rest = md.slice(start);
  #|   const nextSection = rest.search(/^##\s/m);
  #|   const section = (nextSection > 0 ? rest.slice(0, nextSection) : rest).trim();
  #|   if (/^\s*None\.?\s*$/i.test(section)) return false;
  #|   if (/no exceptions/i.test(section)) return false;
  #|   if (!/`\w+`/.test(section) && !/\{\{/.test(section) && !/<code>/.test(section)) return false;
  #|   if (/gl\.\w+/.test(section) && !/Error/.test(section) && !/\{\{jsxref/.test(section)) return false;
  #|   if (/INVALID_\w+/.test(section) && !/Error/.test(section) && !/\{\{jsxref/.test(section) && !/<code>\w+Error/.test(section)) return false;
  #|   return true;
  #| }

///|
/// Apply throws overrides JSON to a ThrowsMap.
/// JSON: { "add": { "I.m": ["E"], "I.a.setter": ["E"] }, "remove": ["I.m"] }
/// Returns added_count * 1000 + removed_count (packed).
extern "js" fn apply_throws_overrides_js(
  map : ThrowsMap,
  json_str : String,
) -> Int =
  #| (map, s) => {
  #|   const o = JSON.parse(s);
  #|   let added = 0, removed = 0;
  #|   if (o.add) {
  #|     for (const [key, exceptions] of Object.entries(o.add)) {
  #|       if (key.endsWith('.setter')) {
  #|         const parts = key.split('.');
  #|         const iface = parts[0], attr = parts[1];
  #|         map.set(iface + '.set_' + attr, exceptions);
  #|         map.set(iface + '.' + attr, exceptions);
  #|       } else {
  #|         map.set(key, exceptions);
  #|       }
  #|       added++;
  #|     }
  #|   }
  #|   if (o.remove) {
  #|     for (const key of o.remove) {
  #|       if (key.endsWith('.setter')) {
  #|         const parts = key.split('.');
  #|         const iface = parts[0], attr = parts[1];
  #|         map.delete(iface + '.set_' + attr);
  #|         map.delete(iface + '.' + attr);
  #|       } else {
  #|         map.delete(key);
  #|       }
  #|       removed++;
  #|     }
  #|   }
  #|   return added * 1000 + removed;
  #| }

///|
/// Convert string to lowercase (JS String.toLowerCase)
extern "js" fn to_lower_case(s : String) -> String =
  #| (s) => s.toLowerCase()

///|
/// Create a new JS string array
extern "js" fn create_js_string_array() -> JsArray =
  #| () => []

///|
/// Push a string to a JS string array
extern "js" fn push_js_string_array(arr : JsArray, s : String) -> Unit =
  #| (arr, s) => arr.push(s)
