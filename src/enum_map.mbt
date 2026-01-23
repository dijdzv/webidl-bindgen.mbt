// Enum マップ操作

///|
/// enum マップから値リストを取得
pub fn lookup_enum(
  enum_map : Array[(String, Array[String])],
  name : String,
) -> Array[String]? {
  for pair in enum_map {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// enum 配列ルックアップ式を生成
/// 例: ['value1', 'value2'][index_expr]
pub fn gen_enum_array_lookup(values : Array[String], index_expr : String) -> String {
  let result = StringBuilder::new()
  result.write_string("[")
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string("'")
    result.write_string(values[i])
    result.write_string("'")
  }
  result.write_string("][")
  result.write_string(index_expr)
  result.write_string("]")
  result.to_string()
}

///|
/// nullable enum 配列ルックアップ式を生成（null チェック付き）
/// 例: (var_name != null ? ['value1', 'value2'][var_name] : null)
pub fn gen_nullable_enum_array_lookup(
  values : Array[String],
  var_name : String,
) -> String {
  let result = StringBuilder::new()
  result.write_string("(")
  result.write_string(var_name)
  result.write_string(" != null ? [")
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string("'")
    result.write_string(values[i])
    result.write_string("'")
  }
  result.write_string("][")
  result.write_string(var_name)
  result.write_string("] : null)")
  result.to_string()
}
