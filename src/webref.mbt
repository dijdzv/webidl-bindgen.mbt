// @webref/idl FFI - Web仕様からWebIDLを取得
//
// @webref/idl は W3C/WHATWG の Web 仕様から WebIDL 定義を取得するライブラリ
// https://www.npmjs.com/package/@webref/idl

///|
/// 仕様データを格納する型 (JS オブジェクト)
pub type SpecsData

///|
/// 仕様オブジェクトを格納する型 (個別の仕様)
pub type SpecObject

// =============================================================================
// Promise を返す FFI
// =============================================================================

///|
/// @webref/idl の listAll() を呼び出し、Promise<SpecsData> を返す
extern "js" fn list_all_specs_promise() -> @js_async.Promise[SpecsData] =
  #| () => require('@webref/idl').listAll()

///|
/// 仕様オブジェクトから WebIDL テキストを取得し、Promise<String> を返す
extern "js" fn get_idl_text_promise(
  spec_obj : SpecObject,
) -> @js_async.Promise[String] =
  #| (specObj) => {
  #|   if (!specObj || typeof specObj.text !== 'function') {
  #|     return Promise.resolve('');
  #|   }
  #|   return specObj.text();
  #| }

// =============================================================================
// 同期 FFI (即座に結果を返せるもの)
// =============================================================================

///|
/// 仕様データから特定の仕様オブジェクトを取得
pub extern "js" fn get_spec_object(
  specs : SpecsData,
  spec_name : String,
) -> SpecObject =
  #| (specs, specName) => specs[specName]

///|
/// 仕様オブジェクトの存在チェック
pub extern "js" fn spec_exists(specs : SpecsData, spec_name : String) -> Bool =
  #| (specs, specName) => specs[specName] !== undefined

///|
/// 仕様データから仕様名の一覧を取得
pub extern "js" fn get_spec_names(specs : SpecsData) -> JsArray =
  #| (specs) => Object.keys(specs)

///|
/// 配列から文字列を取得
pub extern "js" fn get_string_from_array(arr : JsArray, index : Int) -> String =
  #| (arr, index) => arr[index] || ''

// =============================================================================
// 高レベル async API
// =============================================================================

///|
/// @webref/idl の listAll() を呼び出し、全仕様のメタデータを取得
pub async fn list_all_specs() -> SpecsData {
  list_all_specs_promise().wait()
}

///|
/// 仕様オブジェクトから WebIDL テキストを取得
pub async fn get_spec_idl_text(spec_obj : SpecObject) -> String {
  get_idl_text_promise(spec_obj).wait()
}

///|
/// 仕様データから直接 WebIDL テキストを取得（便利関数）
pub async fn get_idl_by_name(specs : SpecsData, spec_name : String) -> String {
  let spec_obj = get_spec_object(specs, spec_name)
  get_spec_idl_text(spec_obj)
}

///|
/// 仕様のロード結果
pub struct SpecLoadResult {
  spec_name : String
  definitions : Array[Definition]
  success : Bool
  error_message : String
}

///|
/// 複数仕様をロードし、全定義を統合
pub async fn load_multiple_specs(
  specs : SpecsData,
  spec_names : Array[String],
  show_progress : Bool,
) -> Array[SpecLoadResult] {
  let results : Array[SpecLoadResult] = []
  let total = spec_names.length()
  let mut current = 0
  for spec_name in spec_names {
    current = current + 1
    if show_progress {
      println(
        "Processing: " +
        spec_name +
        " [" +
        current.to_string() +
        "/" +
        total.to_string() +
        "]",
      )
    }

    // Check if spec exists
    if not(spec_exists(specs, spec_name)) {
      results.push({
        spec_name,
        definitions: [],
        success: false,
        error_message: "Spec not found: " + spec_name,
      })
      continue
    }

    // Load IDL text
    let idl_text = get_idl_by_name(specs, spec_name)
    if idl_text == "" {
      results.push({
        spec_name,
        definitions: [],
        success: false,
        error_message: "Empty IDL for spec: " + spec_name,
      })
      continue
    }

    // Parse IDL
    let parse_result = parse_webidl_raw(idl_text)
    if not(is_parse_success(parse_result)) {
      let error = get_parse_error(parse_result)
      results.push({
        spec_name,
        definitions: [],
        success: false,
        error_message: "Parse error in " + spec_name + ": " + error,
      })
      continue
    }

    // Convert to definitions
    let definitions = convert_to_definitions(parse_result)
    results.push({ spec_name, definitions, success: true, error_message: "" })
  }
  results
}

///|
/// 全仕様名を配列として取得
pub fn get_all_spec_names(specs : SpecsData) -> Array[String] {
  let js_names = get_spec_names(specs)
  let len = js_array_length(js_names)
  let names : Array[String] = []
  let mut i = 0
  while i < len {
    names.push(get_string_from_array(js_names, i))
    i = i + 1
  }
  names
}

///|
/// ロード結果から全定義を統合
pub fn merge_all_results(results : Array[SpecLoadResult]) -> Array[Definition] {
  results
  .iter()
  .filter(fn(r) { r.success })
  .flat_map(fn(r) { r.definitions.iter() })
  .collect()
}
