// Fetch algorithms data from webref GitHub for throws detection

///|
/// Type for throws map (JS Map<string, string[]>)
pub type ThrowsMap

///|
/// Build throws map for a single spec.
/// Returns a JS Map: "Interface.method" -> ["ExceptionName", ...]
/// Uses algorithms JSON + spec HTML + dfns JSON from webref.
extern "js" fn build_throws_map_promise(
  spec_name : String,
) -> @js_async.Promise[ThrowsMap] =
  #| (specName) => require('./throws_builder.cjs')(specName)

///|
/// Build throws map for a single spec (async wrapper)
pub async fn build_throws_map(spec_name : String) -> ThrowsMap {
  build_throws_map_promise(spec_name).wait()
}

///|
/// Get throws list for a specific method from throws map.
/// key format: "Interface.method"
/// Returns JS array of exception names, or empty array if not found.
pub extern "js" fn get_throws(
  throws_map : ThrowsMap,
  interface_name : String,
  method_name : String,
) -> JsArray =
  #| (map, iface, method) => {
  #|   const key = iface + '.' + method;
  #|   return map.get(key) || [];
  #| }

///|
/// Get throws list for a constructor from throws map.
/// key format: "Interface.constructor"
pub extern "js" fn get_constructor_throws(
  throws_map : ThrowsMap,
  interface_name : String,
) -> JsArray =
  #| (map, iface) => {
  #|   return map.get(iface + '.constructor') || [];
  #| }

///|
/// Get throws map size (for stats)
pub extern "js" fn throws_map_size(throws_map : ThrowsMap) -> Int =
  #| (map) => map.size

///|
/// Convert JS string array to MoonBit Array[String]
pub fn js_array_to_strings(arr : JsArray) -> Array[String] {
  let len = js_array_length(arr)
  let result : Array[String] = []
  for i = 0; i < len; i = i + 1 {
    result.push(get_string_from_array(arr, i))
  }
  result
}
