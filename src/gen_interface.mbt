// Interface binding 生成ロジック

/// inline Union の収集用型（Union 名 → メンバー型）
pub struct InlineUnionCollector {
  entries : Array[(String, Array[IdlType])]
}

///|
/// 空のコレクタを作成
pub fn InlineUnionCollector::new() -> InlineUnionCollector {
  { entries: [] }
}

///|
/// コレクタに追加
pub fn InlineUnionCollector::push(
  self : InlineUnionCollector,
  entry : (String, Array[IdlType])
) -> Unit {
  self.entries.push(entry)
}

///|
/// コレクタのイテレーション用
pub fn InlineUnionCollector::iter(
  self : InlineUnionCollector
) -> Iter[(String, Array[IdlType])] {
  self.entries.iter()
}

///|
/// コレクタの長さ
pub fn InlineUnionCollector::length(self : InlineUnionCollector) -> Int {
  self.entries.length()
}

///|
/// WebIDL 型を MoonBit 型に変換（inline Union を収集）
pub fn idl_type_to_moonbit_collecting(
  idl_type : IdlType,
  collector : InlineUnionCollector
) -> String {
  match idl_type {
    Primitive(name) =>
      // WebIDL プリミティブ → MoonBit
      match name {
        "boolean" => "Bool"
        "byte"
        | "octet"
        | "short"
        | "unsigned short"
        | "long"
        | "unsigned long" => "Int"
        "long long" | "unsigned long long" => "Int64"
        "float" | "unrestricted float" | "double" | "unrestricted double" =>
          "Double"
        _ => "JsValue" // 未知の型はJsValue
      }
    String => "String"
    Void => "Unit"
    Nullable(inner) => {
      let inner_type = idl_type_to_moonbit_collecting(inner, collector)
      // 二重 nullable を防ぐ
      if str_ends_with_question(inner_type) {
        inner_type
      } else {
        inner_type + "?"
      }
    }
    Named(name) => {
      // 小文字始まりの型名は JsValue に変換（object など無効な型名）
      let first_char = get_str_first_char(name)
      if first_char >= 'a' && first_char <= 'z' {
        "JsValue"
      } else {
        name
      }
    }
    Sequence(inner) => {
      let inner_type = idl_type_to_moonbit_collecting(inner, collector)
      "Array[" + inner_type + "]"
    }
    Promise(inner) => {
      let inner_type = idl_type_to_moonbit_collecting(inner, collector)
      "Promise[" + inner_type + "]"
    }
    Union(members) => {
      // 1メンバーの Union はその型を直接使う
      if members.length() == 1 {
        return idl_type_to_moonbit_collecting(members[0], collector)
      }
      // inline Union の名前を生成し、コレクタに追加
      let union_name = generate_inline_union_name(members)
      // 既に追加済みでなければ追加
      if not(has_inline_union(collector, union_name)) {
        collector.push((union_name, members))
      }
      union_name
    }
    Any => "JsValue"
  }
}

///|
/// WebIDL 型を MoonBit 型に変換（inline Union は生成名を返す）
pub fn idl_type_to_moonbit(idl_type : IdlType) -> String {
  match idl_type {
    Primitive(name) =>
      match name {
        "boolean" => "Bool"
        "byte"
        | "octet"
        | "short"
        | "unsigned short"
        | "long"
        | "unsigned long" => "Int"
        "long long" | "unsigned long long" => "Int64"
        "float" | "unrestricted float" | "double" | "unrestricted double" =>
          "Double"
        _ => "JsValue"
      }
    String => "String"
    Void => "Unit"
    Nullable(inner) => {
      let inner_type = idl_type_to_moonbit(inner)
      if str_ends_with_question(inner_type) {
        inner_type
      } else {
        inner_type + "?"
      }
    }
    Named(name) => {
      let first_char = get_str_first_char(name)
      if first_char >= 'a' && first_char <= 'z' {
        "JsValue"
      } else {
        name
      }
    }
    Sequence(inner) => {
      let inner_type = idl_type_to_moonbit(inner)
      "Array[" + inner_type + "]"
    }
    Promise(inner) => {
      let inner_type = idl_type_to_moonbit(inner)
      "Promise[" + inner_type + "]"
    }
    Union(members) => {
      // 1メンバーの Union はその型を直接使う
      if members.length() == 1 {
        return idl_type_to_moonbit(members[0])
      }
      // inline Union の名前を生成して返す
      generate_inline_union_name(members)
    }
    Any => "JsValue"
  }
}

///|
/// inline Union の名前を生成（メンバー型から一意な名前を生成）
fn generate_inline_union_name(members : Array[IdlType]) -> String {
  let parts : Array[String] = []
  for mem in members {
    let part = get_union_member_name(mem)
    if part != "" {
      parts.push(part)
    }
  }
  // メンバー名を結合（例: StringOrCanvasGradientOrCanvasPattern）
  let result = StringBuilder::new()
  for i, part in parts {
    if i > 0 {
      result.write_string("Or")
    }
    result.write_string(part)
  }
  result.to_string()
}

///|
/// Union メンバーの型名を取得（名前生成用）
fn get_union_member_name(idl_type : IdlType) -> String {
  match idl_type {
    Primitive(name) =>
      match name {
        "DOMString" | "USVString" | "ByteString" => "String"
        "boolean" => "Bool"
        "byte" | "octet" | "short" | "unsigned short" | "long" | "unsigned long" =>
          "Int"
        "long long" | "unsigned long long" => "Int64"
        "float" | "unrestricted float" | "double" | "unrestricted double" =>
          "Double"
        // その他のプリミティブ型も名前を持つように
        _ => capitalize_first(name)
      }
    String => "String"
    Named(name) => {
      // 小文字始まりの場合は大文字化（bigint など）
      let first_char = get_str_first_char(name)
      if first_char >= 'a' && first_char <= 'z' {
        capitalize_first(name)
      } else {
        name
      }
    }
    Sequence(inner) => {
      let inner_name = get_union_member_name(inner)
      if inner_name != "" {
        "ArrayOf" + inner_name
      } else {
        "Array"
      }
    }
    Nullable(inner) => {
      let inner_name = get_union_member_name(inner)
      if inner_name != "" {
        "Nullable" + inner_name
      } else {
        "Nullable"
      }
    }
    Promise(inner) => {
      let inner_name = get_union_member_name(inner)
      if inner_name != "" {
        "PromiseOf" + inner_name
      } else {
        "Promise"
      }
    }
    Union(members) => {
      // ネストされた Union は再帰的に名前を生成
      generate_inline_union_name(members)
    }
    Void => "Void"
    Any => "Any"
  }
}

///|
/// 文字列の最初の文字を大文字にする
fn capitalize_first(s : String) -> String {
  let result = StringBuilder::new()
  let mut first = true
  for c in s {
    if first {
      // 小文字なら大文字に変換
      if c >= 'a' && c <= 'z' {
        result.write_char((c.to_int() - 32).unsafe_to_char())
      } else {
        result.write_char(c)
      }
      first = false
    } else {
      result.write_char(c)
    }
  }
  result.to_string()
}

///|
/// コレクタに指定名の Union が既に存在するかチェック
fn has_inline_union(collector : InlineUnionCollector, name : String) -> Bool {
  for entry in collector.iter() {
    if entry.0 == name {
      return true
    }
  }
  false
}

///|
/// 文字列が ? で終わるかチェック
fn str_ends_with_question(s : String) -> Bool {
  let mut last_char = ' '
  for c in s {
    last_char = c
  }
  last_char == '?'
}

///|
/// 文字列の最初の文字を取得
fn get_str_first_char(s : String) -> Char {
  for c in s {
    return c
  }
  ' '
}

///|
/// 文字列が空かチェック
fn is_empty_op_name(s : String) -> Bool {
  for _ in s {
    return false
  }
  true
}

///|
/// 文字列の先頭1文字を削除
fn remove_leading_char(s : String) -> String {
  if s.length() <= 1 {
    return ""
  }
  // Build new string without first character
  let result = StringBuilder::new()
  let mut skip_first = true
  for c in s {
    if skip_first {
      skip_first = false
      continue
    }
    result.write_char(c)
  }
  result.to_string()
}

///|
/// snake_case を変換（ハイフンもアンダースコアに変換）
pub fn to_snake_case(name : String) -> String {
  let result = StringBuilder::new()
  let mut first = true
  for c in name {
    if c >= 'A' && c <= 'Z' {
      if not(first) {
        result.write_char('_')
      }
      // 大文字を小文字に変換 (ASCII: 'A'=65, 'a'=97, diff=32)
      let lower_code = c.to_int() + 32
      let lower = lower_code.unsafe_to_char()
      result.write_char(lower)
    } else if c == '-' {
      // ハイフンはアンダースコアに変換
      result.write_char('_')
    } else {
      result.write_char(c)
    }
    first = false
  }
  result.to_string()
}

///|
/// enum マップから値リストを取得
fn get_enum_values(
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
/// Static Operation から extern js fn を生成
pub fn gen_static_operation(
  interface_name : String,
  op : OperationDef,
  enum_map : Array[(String, Array[String])],
) -> String {
  gen_static_operation_with_suffix(interface_name, op, enum_map, "")
}

///|
/// Static Operation から extern js fn を生成（サフィックス付き）
pub fn gen_static_operation_with_suffix(
  interface_name : String,
  op : OperationDef,
  enum_map : Array[(String, Array[String])],
  suffix : String,
) -> String {
  // 名前なしの特殊メソッドはスキップ
  if is_empty_op_name(op.name) {
    return ""
  }
  let base_fn_name = escape_reserved(to_snake_case(op.name))
  let fn_name = if suffix == "" {
    base_fn_name
  } else {
    base_fn_name + suffix
  }
  let return_type = idl_type_to_moonbit(op.return_type)

  // 引数リスト生成（self なし）
  let args = StringBuilder::new()
  let args_len = op.arguments.length()
  for i = 0; i < args_len; i = i + 1 {
    let arg = op.arguments[i]
    if i > 0 {
      args.write_string(", ")
    }
    // 引数名も予約語をエスケープ
    args.write_string(escape_reserved(to_snake_case(arg.name)))
    args.write_string(" : ")
    args.write_string(idl_type_to_moonbit(arg.idl_type))
  }

  // JS 呼び出し引数（enum は配列ルックアップで文字列に変換）
  let js_call_args = StringBuilder::new()
  for i = 0; i < args_len; i = i + 1 {
    let arg = op.arguments[i]
    if i > 0 {
      js_call_args.write_string(", ")
    }
    let arg_name = escape_reserved(to_snake_case(arg.name))
    // 引数の型が enum かチェック
    match arg.idl_type {
      Named(type_name) =>
        match get_enum_values(enum_map, type_name) {
          Some(values) => {
            // enum は配列ルックアップで文字列に変換
            js_call_args.write_string("[")
            for j = 0; j < values.length(); j = j + 1 {
              if j > 0 {
                js_call_args.write_string(", ")
              }
              js_call_args.write_string("'")
              js_call_args.write_string(values[j])
              js_call_args.write_string("'")
            }
            js_call_args.write_string("][")
            js_call_args.write_string(arg_name)
            js_call_args.write_string("]")
          }
          None => js_call_args.write_string(arg_name)
        }
      Nullable(Named(type_name)) =>
        match get_enum_values(enum_map, type_name) {
          Some(values) => {
            // nullable enum も配列ルックアップ（null チェック付き）
            js_call_args.write_string("(")
            js_call_args.write_string(arg_name)
            js_call_args.write_string(" != null ? [")
            for j = 0; j < values.length(); j = j + 1 {
              if j > 0 {
                js_call_args.write_string(", ")
              }
              js_call_args.write_string("'")
              js_call_args.write_string(values[j])
              js_call_args.write_string("'")
            }
            js_call_args.write_string("][")
            js_call_args.write_string(arg_name)
            js_call_args.write_string("] : null)")
          }
          None => js_call_args.write_string(arg_name)
        }
      _ => js_call_args.write_string(arg_name)
    }
  }

  // JS側の引数リスト（変数名のみ）
  let js_params = StringBuilder::new()
  for i = 0; i < args_len; i = i + 1 {
    let arg = op.arguments[i]
    if i > 0 {
      js_params.write_string(", ")
    }
    js_params.write_string(escape_reserved(to_snake_case(arg.name)))
  }
  let result = StringBuilder::new()
  result.write_string("pub extern \"js\" fn ")
  result.write_string(interface_name)
  result.write_string("::")
  result.write_string(fn_name)
  result.write_string("(")
  result.write_string(args.to_string())
  result.write_string(") -> ")
  result.write_string(return_type)
  result.write_string(" =\n")
  result.write_string("  #| (")
  result.write_string(js_params.to_string())
  result.write_string(") => ")
  result.write_string(interface_name)
  result.write_string(".")
  result.write_string(op.name)
  result.write_string("(")
  result.write_string(js_call_args.to_string())
  result.write_string(")\n")
  result.to_string()
}

///|
/// Special operation (getter/setter/deleter) から extern js fn を生成
pub fn gen_special_operation(
  interface_name : String,
  op : OperationDef,
  special_type : String,
) -> String {
  match special_type {
    "getter" => {
      // getter には2種類ある：
      // 1. インデックスベース: getter T? item(unsigned long index)
      // 2. 名前ベース: getter T? namedItem(DOMString name)
      let args_len = op.arguments.length()
      if args_len != 1 {
        return "" // getter は引数1つのはず
      }
      let arg = op.arguments[0]
      let arg_type = idl_type_to_moonbit(arg.idl_type)
      let return_type = idl_type_to_moonbit(op.return_type)

      // 引数の型でインデックスか名前か判定
      let is_index_getter = match arg.idl_type {
        Primitive(_) => true // unsigned long など
        _ => false
      }
      let fn_name = if is_index_getter { "get" } else { "get_named" }
      let arg_name = escape_reserved(to_snake_case(arg.name))
      let result = StringBuilder::new()
      result.write_string("pub extern \"js\" fn ")
      result.write_string(interface_name)
      result.write_string("::")
      result.write_string(fn_name)
      result.write_string("(self : ")
      result.write_string(interface_name)
      result.write_string(", ")
      result.write_string(arg_name)
      result.write_string(" : ")
      result.write_string(arg_type)
      result.write_string(") -> ")
      result.write_string(return_type)
      result.write_string(" =\n")
      result.write_string("  #| (self, ")
      result.write_string(arg_name)
      result.write_string(") => self[")
      result.write_string(arg_name)
      result.write_string("]\n")
      result.to_string()
    }
    "setter" => {
      // setter は setter undefined (unsigned long index, T value) の形式
      let args_len = op.arguments.length()
      if args_len != 2 {
        return "" // setter は引数2つのはず
      }
      let index_arg = op.arguments[0]
      let value_arg = op.arguments[1]
      let index_type = idl_type_to_moonbit(index_arg.idl_type)
      let value_type = idl_type_to_moonbit(value_arg.idl_type)
      let index_name = escape_reserved(to_snake_case(index_arg.name))
      let value_name = escape_reserved(to_snake_case(value_arg.name))
      let result = StringBuilder::new()
      result.write_string("pub extern \"js\" fn ")
      result.write_string(interface_name)
      result.write_string("::set(self : ")
      result.write_string(interface_name)
      result.write_string(", ")
      result.write_string(index_name)
      result.write_string(" : ")
      result.write_string(index_type)
      result.write_string(", ")
      result.write_string(value_name)
      result.write_string(" : ")
      result.write_string(value_type)
      result.write_string(") -> Unit =\n")
      result.write_string("  #| (self, ")
      result.write_string(index_name)
      result.write_string(", ")
      result.write_string(value_name)
      result.write_string(") => { self[")
      result.write_string(index_name)
      result.write_string("] = ")
      result.write_string(value_name)
      result.write_string(" }\n")
      result.to_string()
    }
    "deleter" => {
      // deleter は deleter undefined (T key) の形式
      let args_len = op.arguments.length()
      if args_len != 1 {
        return "" // deleter は引数1つのはず
      }
      let arg = op.arguments[0]
      let arg_type = idl_type_to_moonbit(arg.idl_type)
      let arg_name = escape_reserved(to_snake_case(arg.name))
      let result = StringBuilder::new()
      result.write_string("pub extern \"js\" fn ")
      result.write_string(interface_name)
      result.write_string("::delete(self : ")
      result.write_string(interface_name)
      result.write_string(", ")
      result.write_string(arg_name)
      result.write_string(" : ")
      result.write_string(arg_type)
      result.write_string(") -> Unit =\n")
      result.write_string("  #| (self, ")
      result.write_string(arg_name)
      result.write_string(") => { delete self[")
      result.write_string(arg_name)
      result.write_string("] }\n")
      result.to_string()
    }
    _ => ""
  }
}

///|
/// Operation から extern js fn を生成
pub fn gen_operation(
  interface_name : String,
  op : OperationDef,
  enum_map : Array[(String, Array[String])],
) -> String {
  // 名前なしの通常メソッドはスキップ
  // (special operation は gen_interface_binding で処理)
  if is_empty_op_name(op.name) {
    return ""
  }
  let fn_name = escape_reserved(to_snake_case(op.name))
  let return_type = idl_type_to_moonbit(op.return_type)

  // 引数リスト生成
  let args = StringBuilder::new()
  args.write_string("self : ")
  args.write_string(interface_name)
  let args_len = op.arguments.length()
  for i = 0; i < args_len; i = i + 1 {
    let arg = op.arguments[i]
    args.write_string(", ")
    // 引数名も予約語をエスケープ
    args.write_string(escape_reserved(to_snake_case(arg.name)))
    args.write_string(" : ")
    args.write_string(idl_type_to_moonbit(arg.idl_type))
  }

  // JS呼び出しコード生成
  let js_args = StringBuilder::new()
  js_args.write_string("self")
  for i = 0; i < args_len; i = i + 1 {
    let arg = op.arguments[i]
    js_args.write_string(", ")
    js_args.write_string(escape_reserved(to_snake_case(arg.name)))
  }

  // JS 呼び出し引数（enum は配列ルックアップで文字列に変換）
  let js_call_args = StringBuilder::new()
  for i = 0; i < args_len; i = i + 1 {
    let arg = op.arguments[i]
    if i > 0 {
      js_call_args.write_string(", ")
    }
    let arg_name = escape_reserved(to_snake_case(arg.name))
    // 引数の型が enum かチェック
    match arg.idl_type {
      Named(type_name) =>
        match get_enum_values(enum_map, type_name) {
          Some(values) => {
            // enum は配列ルックアップで文字列に変換
            js_call_args.write_string("[")
            for j = 0; j < values.length(); j = j + 1 {
              if j > 0 {
                js_call_args.write_string(", ")
              }
              js_call_args.write_string("'")
              js_call_args.write_string(values[j])
              js_call_args.write_string("'")
            }
            js_call_args.write_string("][")
            js_call_args.write_string(arg_name)
            js_call_args.write_string("]")
          }
          None => js_call_args.write_string(arg_name)
        }
      Nullable(Named(type_name)) =>
        match get_enum_values(enum_map, type_name) {
          Some(values) => {
            // nullable enum も配列ルックアップ（null チェック付き）
            js_call_args.write_string("(")
            js_call_args.write_string(arg_name)
            js_call_args.write_string(" != null ? [")
            for j = 0; j < values.length(); j = j + 1 {
              if j > 0 {
                js_call_args.write_string(", ")
              }
              js_call_args.write_string("'")
              js_call_args.write_string(values[j])
              js_call_args.write_string("'")
            }
            js_call_args.write_string("][")
            js_call_args.write_string(arg_name)
            js_call_args.write_string("] : null)")
          }
          None => js_call_args.write_string(arg_name)
        }
      _ => js_call_args.write_string(arg_name)
    }
  }
  let result = StringBuilder::new()
  result.write_string("pub extern \"js\" fn ")
  result.write_string(interface_name)
  result.write_string("::")
  result.write_string(fn_name)
  result.write_string("(")
  result.write_string(args.to_string())
  result.write_string(") -> ")
  result.write_string(return_type)
  result.write_string(" =\n")
  result.write_string("  #| (")
  result.write_string(js_args.to_string())
  result.write_string(") => self.")
  result.write_string(op.name)
  result.write_string("(")
  result.write_string(js_call_args.to_string())
  result.write_string(")\n")
  result.to_string()
}

///|
/// 同名operationをグループ化し、引数数でソート
/// Map型の代わりに Array[(String, Array[OperationDef])] を返す
pub fn group_operations_by_name(
  members : Array[InterfaceMember]
) -> Array[(String, Array[OperationDef])] {
  let groups : Array[(String, Array[OperationDef])] = []

  // Operation のみを抽出してグループ化
  for mem in members {
    match mem {
      Operation(op) => {
        // 空名のoperationはスキップ
        if is_empty_op_name(op.name) {
          continue
        }

        // 既存のグループを探す
        let mut found = false
        for i = 0; i < groups.length(); i = i + 1 {
          let (name, ops) = groups[i]
          if name == op.name {
            ops.push(op)
            groups[i] = (name, ops)
            found = true
            break
          }
        }

        // 新しいグループを作成
        if not(found) {
          let new_group : Array[OperationDef] = [op]
          groups.push((op.name, new_group))
        }
      }
      _ => ()
    }
  }

  // 各グループ内で「必須引数」数の少ない順にソート
  // optional引数を持つoperationは、最初のoptional引数の位置を必須引数数とする
  for i = 0; i < groups.length(); i = i + 1 {
    let (name, ops) = groups[i]
    // バブルソート（必須引数数の昇順）
    for j = 0; j < ops.length(); j = j + 1 {
      for k = j + 1; k < ops.length(); k = k + 1 {
        // 必須引数数を計算
        let first_optional_j = find_first_optional_arg_index(ops[j].arguments)
        let required_args_j = if first_optional_j < 0 {
          ops[j].arguments.length()
        } else {
          first_optional_j
        }
        let first_optional_k = find_first_optional_arg_index(ops[k].arguments)
        let required_args_k = if first_optional_k < 0 {
          ops[k].arguments.length()
        } else {
          first_optional_k
        }
        if required_args_j > required_args_k {
          // swap
          let temp = ops[j]
          ops[j] = ops[k]
          ops[k] = temp
        }
      }
    }
    groups[i] = (name, ops)
  }

  groups
}

///|
/// オーバーロードのサフィックスを生成（差分ベース）
///
/// Rust web-sysの命名規則に従い、差分引数から "_with_xxx_and_yyy" 形式のサフィックスを生成します。
/// 注意: 同じ引数数で異なる型のオーバーロードがある場合は gen_overload_suffix_from_all を使用してください。
///
/// # 引数
/// - `base_args`: 最小シグネチャの引数配列
/// - `full_args`: 現在のオーバーロードの引数配列
///
/// # 戻り値
/// - "_with_xxx_and_yyy" 形式のサフィックス（ベース版は空文字列）
///
/// # 例
/// ```moonbit
/// // base_args: [image, dx, dy], full_args: [image, dx, dy]
/// // → ""
///
/// // base_args: [image, dx, dy], full_args: [image, dx, dy, dw, dh]
/// // → "_with_dw_and_dh"
///
/// // base_args: [data, dx, dy], full_args: [data, dx, dy, dirtyX, dirtyY, dirtyWidth, dirtyHeight]
/// // → "_with_dirty_x_and_dirty_y_and_dirty_width_and_dirty_height"
/// ```
pub fn gen_overload_suffix(
  base_args : Array[Argument],
  full_args : Array[Argument],
) -> String {
  let base_len = base_args.length()
  let full_len = full_args.length()

  // 差分がない場合は空文字列
  if base_len == full_len {
    return ""
  }

  // 差分引数のsnake_case名を収集
  let result = StringBuilder::new()
  result.write_string("_with")

  for i = base_len; i < full_len; i = i + 1 {
    let arg_name = to_snake_case(full_args[i].name)
    result.write_string("_")
    result.write_string(arg_name)
    if i < full_len - 1 {
      result.write_string("_and")
    }
  }

  result.to_string()
}

///|
/// 引数の型名を snake_case に変換
fn arg_type_to_snake_case(arg_type : IdlType) -> String {
  match arg_type {
    Named(name) => to_snake_case(name)
    String => "string"
    Primitive(name) => to_snake_case(name)
    Nullable(inner) => arg_type_to_snake_case(inner)
    Sequence(_) => "array"
    Promise(_) => "promise"
    Union(_) => "union"
    Any => "any"
    Void => "void"
  }
}

///|
/// オーバーロードのサフィックスを全引数から生成
///
/// 同じ引数数で異なる型のオーバーロードがある場合に使用します。
/// 全ての引数名から "_with_xxx_and_yyy" 形式のサフィックスを生成します。
/// 引数名が同じ場合は型名も含めます。
///
/// # 引数
/// - `args`: 引数配列
///
/// # 戻り値
/// - "_with_xxx_and_yyy" 形式のサフィックス（引数が0個の場合は空文字列）
///
/// # 例
/// ```moonbit
/// // args: [name: String]
/// // → "_with_name"
///
/// // args: [data: Blob]
/// // → "_with_data_blob"  (型名を含む)
///
/// // args: [name: String, value: Int]
/// // → "_with_name_and_value"
/// ```
pub fn gen_overload_suffix_from_all(args : Array[Argument]) -> String {
  let len = args.length()

  // 引数がない場合は空文字列
  if len == 0 {
    return ""
  }

  // 全引数のsnake_case名を収集
  let result = StringBuilder::new()
  result.write_string("_with")

  for i = 0; i < len; i = i + 1 {
    let arg = args[i]
    let arg_name = to_snake_case(arg.name)
    result.write_string("_")
    result.write_string(arg_name)

    // 型名も追加（引数名だけでは区別できない場合のため）
    // シンプルな型（Named）の場合のみ追加
    match arg.idl_type {
      Named(_) => {
        result.write_string("_")
        result.write_string(arg_type_to_snake_case(arg.idl_type))
      }
      _ => ()
    }

    if i < len - 1 {
      result.write_string("_and")
    }
  }

  result.to_string()
}

///|
/// optional引数の最初のインデックスを取得（なければ-1）
fn find_first_optional_arg_index(args : Array[Argument]) -> Int {
  for i = 0; i < args.length(); i = i + 1 {
    if args[i].optional {
      return i
    }
  }
  -1
}

///|
/// 指定された引数数でOperation を生成
/// fn_suffix: 関数名に付けるサフィックス（空文字列の場合はなし）
pub fn gen_operation_with_arg_count(
  interface_name : String,
  op : OperationDef,
  enum_map : Array[(String, Array[String])],
  arg_count : Int,
  fn_suffix : String,
) -> String {
  if is_empty_op_name(op.name) {
    return ""
  }
  let base_fn_name = escape_reserved(to_snake_case(op.name))
  let fn_name = if fn_suffix == "" {
    base_fn_name
  } else {
    base_fn_name + "_" + fn_suffix
  }
  let return_type = idl_type_to_moonbit(op.return_type)

  // 引数リスト生成（arg_count個まで）
  let args = StringBuilder::new()
  args.write_string("self : ")
  args.write_string(interface_name)
  for i = 0; i < arg_count; i = i + 1 {
    let arg = op.arguments[i]
    args.write_string(", ")
    args.write_string(escape_reserved(to_snake_case(arg.name)))
    args.write_string(" : ")
    args.write_string(idl_type_to_moonbit(arg.idl_type))
  }

  // JS呼び出しコード生成
  let js_args = StringBuilder::new()
  js_args.write_string("self")
  for i = 0; i < arg_count; i = i + 1 {
    let arg = op.arguments[i]
    js_args.write_string(", ")
    js_args.write_string(escape_reserved(to_snake_case(arg.name)))
  }

  // JS 呼び出し引数（enum は配列ルックアップで文字列に変換）
  let js_call_args = StringBuilder::new()
  for i = 0; i < arg_count; i = i + 1 {
    let arg = op.arguments[i]
    if i > 0 {
      js_call_args.write_string(", ")
    }
    let arg_name = escape_reserved(to_snake_case(arg.name))
    match arg.idl_type {
      Named(type_name) =>
        match get_enum_values(enum_map, type_name) {
          Some(values) => {
            js_call_args.write_string("[")
            for j = 0; j < values.length(); j = j + 1 {
              if j > 0 {
                js_call_args.write_string(", ")
              }
              js_call_args.write_string("'")
              js_call_args.write_string(values[j])
              js_call_args.write_string("'")
            }
            js_call_args.write_string("][")
            js_call_args.write_string(arg_name)
            js_call_args.write_string("]")
          }
          None => js_call_args.write_string(arg_name)
        }
      Nullable(Named(type_name)) =>
        match get_enum_values(enum_map, type_name) {
          Some(values) => {
            js_call_args.write_string("(")
            js_call_args.write_string(arg_name)
            js_call_args.write_string(" != null ? [")
            for j = 0; j < values.length(); j = j + 1 {
              if j > 0 {
                js_call_args.write_string(", ")
              }
              js_call_args.write_string("'")
              js_call_args.write_string(values[j])
              js_call_args.write_string("'")
            }
            js_call_args.write_string("][")
            js_call_args.write_string(arg_name)
            js_call_args.write_string("] : null)")
          }
          None => js_call_args.write_string(arg_name)
        }
      _ => js_call_args.write_string(arg_name)
    }
  }
  let result = StringBuilder::new()
  result.write_string("pub extern \"js\" fn ")
  result.write_string(interface_name)
  result.write_string("::")
  result.write_string(fn_name)
  result.write_string("(")
  result.write_string(args.to_string())
  result.write_string(") -> ")
  result.write_string(return_type)
  result.write_string(" =\n")
  result.write_string("  #| (")
  result.write_string(js_args.to_string())
  result.write_string(") => self.")
  result.write_string(op.name)
  result.write_string("(")
  result.write_string(js_call_args.to_string())
  result.write_string(")\n")
  result.to_string()
}

///|
/// Operation のすべてのバリアントを生成（optional引数対応）
/// 戻り値: (生成されたコード, 登録すべき関数名のリスト)
pub fn gen_operation_variants(
  interface_name : String,
  op : OperationDef,
  enum_map : Array[(String, Array[String])],
) -> (String, Array[String]) {
  let result = StringBuilder::new()
  let fn_names : Array[String] = []
  if is_empty_op_name(op.name) {
    return (result.to_string(), fn_names)
  }
  let first_optional = find_first_optional_arg_index(op.arguments)
  let total_args = op.arguments.length()

  // optional引数がない場合は通常生成
  if first_optional < 0 {
    let code = gen_operation(interface_name, op, enum_map)
    result.write_string(code)
    fn_names.push(escape_reserved(to_snake_case(op.name)))
    return (result.to_string(), fn_names)
  }

  // 必須引数のみのベース版を生成
  let base_fn_name = escape_reserved(to_snake_case(op.name))
  let base_code = gen_operation_with_arg_count(
    interface_name, op, enum_map, first_optional, "",
  )
  result.write_string(base_code)
  result.write_string("\n")
  fn_names.push(base_fn_name)

  // 全引数版を生成（サフィックス付き）
  // 最後のoptional引数の名前をサフィックスにする
  let last_optional_arg = op.arguments[total_args - 1]
  let suffix = "with_" + to_snake_case(last_optional_arg.name)
  let full_code = gen_operation_with_arg_count(
    interface_name, op, enum_map, total_args, suffix,
  )
  result.write_string(full_code)
  fn_names.push(base_fn_name + "_" + suffix)
  (result.to_string(), fn_names)
}

///|
/// オーバーロードされた通常operationの全バリアントを生成
/// グループ内の最小引数版をベース名で、それ以外はサフィックス付きで生成
pub fn gen_overloaded_operations(
  interface_name : String,
  ops : Array[OperationDef],
  enum_map : Array[(String, Array[String])],
  generated_methods : Array[String],
) -> String {
  let result = StringBuilder::new()

  // 空の場合は何も生成しない
  if ops.length() == 0 {
    return ""
  }

  // 単一のoperationの場合は既存のgen_operation_variantsを使用
  if ops.length() == 1 {
    let (code, fn_names) = gen_operation_variants(
      interface_name,
      ops[0],
      enum_map,
    )
    for name in fn_names {
      generated_methods.push(name)
    }
    return code
  }

  // 複数のオーバーロードがある場合
  // 各オーバーロードのoptional引数も考慮して全バリアントを生成

  for i = 0; i < ops.length(); i = i + 1 {
    let op = ops[i]
    let first_optional = find_first_optional_arg_index(op.arguments)
    let total_args = op.arguments.length()

    if first_optional < 0 {
      // optional引数がない場合
      if i == 0 {
        // 最初のオーバーロード（最小引数）はベース名で生成
        let base_fn_name = escape_reserved(to_snake_case(op.name))
        generated_methods.push(base_fn_name)
        result.write_string(gen_operation(interface_name, op, enum_map))
        result.write_string("\n")
      } else {
        // それ以外は全引数からサフィックスを生成（同じ引数数でも区別される）
        let suffix = gen_overload_suffix_from_all(op.arguments)
        let fn_name = escape_reserved(to_snake_case(op.name)) + suffix
        generated_methods.push(fn_name)
        result.write_string(
          gen_operation_with_arg_count(
            interface_name,
            op,
            enum_map,
            total_args,
            remove_leading_char(suffix), // Remove leading underscore
          ),
        )
        result.write_string("\n")
      }
    } else {
      // optional引数がある場合、必須部分と全引数版の両方を生成
      let base_fn_name = escape_reserved(to_snake_case(op.name))

      // 必須引数のみの配列を作成
      let required_args : Array[Argument] = []
      for j = 0; j < first_optional; j = j + 1 {
        required_args.push(op.arguments[j])
      }

      // 必須引数版
      let required_suffix = if i == 0 {
        ""
      } else {
        // 2番目以降のオーバーロードは、必須引数部分から全引数ベースでサフィックス生成
        gen_overload_suffix_from_all(required_args)
      }
      let required_fn_name = base_fn_name + required_suffix
      generated_methods.push(required_fn_name)
      result.write_string(
        gen_operation_with_arg_count(
          interface_name,
          op,
          enum_map,
          first_optional,
          if required_suffix == "" { "" } else { remove_leading_char(required_suffix) },
        ),
      )
      result.write_string("\n")

      // 全引数版（全引数からサフィックス生成）
      let full_suffix = if i == 0 {
        // 最初のオーバーロードの場合は、最後のoptional引数だけ
        let last_optional_arg = op.arguments[total_args - 1]
        "_with_" + to_snake_case(last_optional_arg.name)
      } else {
        // 2番目以降は全引数からサフィックス生成
        gen_overload_suffix_from_all(op.arguments)
      }
      let full_fn_name = base_fn_name + full_suffix
      generated_methods.push(full_fn_name)
      result.write_string(
        gen_operation_with_arg_count(
          interface_name,
          op,
          enum_map,
          total_args,
          remove_leading_char(full_suffix),
        ),
      )
      result.write_string("\n")
    }
  }
  result.to_string()
}

///|
/// オーバーロードされたstatic operationの全バリアントを生成
pub fn gen_overloaded_static_operations(
  interface_name : String,
  ops : Array[OperationDef],
  enum_map : Array[(String, Array[String])],
  generated_methods : Array[String],
) -> String {
  let result = StringBuilder::new()

  // 空の場合は何も生成しない
  if ops.length() == 0 {
    return ""
  }

  // 単一のstatic operationの場合は通常生成
  if ops.length() == 1 {
    let base_fn_name = escape_reserved(to_snake_case(ops[0].name))
    generated_methods.push(base_fn_name)
    result.write_string(gen_static_operation(interface_name, ops[0], enum_map))
    return result.to_string()
  }

  // 複数のオーバーロードがある場合

  for i = 0; i < ops.length(); i = i + 1 {
    let op = ops[i]
    if i == 0 {
      // 最初のオーバーロードはベース名で生成
      let base_fn_name = escape_reserved(to_snake_case(op.name))
      generated_methods.push(base_fn_name)
      result.write_string(gen_static_operation(interface_name, op, enum_map))
      result.write_string("\n")
    } else {
      // それ以外は全引数からサフィックスを生成（同じ引数数でも区別される）
      let suffix = gen_overload_suffix_from_all(op.arguments)
      let fn_name = escape_reserved(to_snake_case(op.name)) + suffix
      generated_methods.push(fn_name)
      result.write_string(
        gen_static_operation_with_suffix(
          interface_name,
          op,
          enum_map,
          suffix,
        ),
      )
      result.write_string("\n")
    }
  }
  result.to_string()
}

///|
/// Attribute getter を生成
pub fn gen_attribute_getter(
  interface_name : String,
  attr : AttributeDef,
) -> String {
  let fn_name = "get_" + to_snake_case(attr.name)
  let return_type = idl_type_to_moonbit(attr.idl_type)
  let result = StringBuilder::new()
  result.write_string("pub extern \"js\" fn ")
  result.write_string(interface_name)
  result.write_string("::")
  result.write_string(fn_name)
  result.write_string("(self : ")
  result.write_string(interface_name)
  result.write_string(") -> ")
  result.write_string(return_type)
  result.write_string(" =\n")
  result.write_string("  #| (self) => self.")
  result.write_string(attr.name)
  result.write_string("\n")
  result.to_string()
}

///|
/// Attribute setter を生成
pub fn gen_attribute_setter(
  interface_name : String,
  attr : AttributeDef,
) -> String {
  if attr.is_readonly {
    return "" // readonly は setter なし
  }
  let fn_name = "set_" + to_snake_case(attr.name)
  let value_type = idl_type_to_moonbit(attr.idl_type)
  let result = StringBuilder::new()
  result.write_string("pub extern \"js\" fn ")
  result.write_string(interface_name)
  result.write_string("::")
  result.write_string(fn_name)
  result.write_string("(self : ")
  result.write_string(interface_name)
  result.write_string(", value : ")
  result.write_string(value_type)
  result.write_string(") -> Unit =\n")
  result.write_string("  #| (self, value) => { self.")
  result.write_string(attr.name)
  result.write_string(" = value }\n")
  result.to_string()
}

///|
/// Const 定数から pub let 宣言を生成
/// 例: const GLenum ARRAY_BUFFER = 0x8892 → pub let webgl_rendering_context_array_buffer : Int = 0x8892
pub fn gen_const(interface_name : String, const_def : ConstDef) -> String {
  let result = StringBuilder::new()

  // 定数名を生成（インターフェース名_定数名）
  // 例: WebGLRenderingContext + ARRAY_BUFFER → webgl_rendering_context_array_buffer
  let interface_prefix = to_snake_case(interface_name)
  let const_suffix = const_name_to_snake_case(const_def.name)
  let const_name = interface_prefix + "_" + const_suffix

  // 型を MoonBit 型に変換（GLenum などは Int にマップ）
  let moonbit_type = const_type_to_moonbit(const_def.idl_type)

  // 値の変換（16進数はそのまま、文字列は引用符付き）
  let value = format_const_value(const_def.value, moonbit_type)

  // コメントで元のインターフェース名と定数名を記載
  result.write_string("// ")
  result.write_string(interface_name)
  result.write_string(".")
  result.write_string(const_def.name)
  result.write_string("\n")

  // pub let 宣言を生成
  result.write_string("pub let ")
  result.write_string(const_name)
  result.write_string(" : ")
  result.write_string(moonbit_type)
  result.write_string(" = ")
  result.write_string(value)
  result.write_string("\n")
  result.to_string()
}

///|
/// 定数名を snake_case に変換（UPPER_CASE → lower_case）
/// WebGL の定数は既にアンダースコア区切りなので、単純に小文字化する
fn const_name_to_snake_case(name : String) -> String {
  let result = StringBuilder::new()
  for c in name {
    if c >= 'A' && c <= 'Z' {
      // 大文字を小文字に変換 (ASCII: 'A'=65, 'a'=97, diff=32)
      let lower_code = c.to_int() + 32
      let lower = lower_code.unsafe_to_char()
      result.write_char(lower)
    } else {
      result.write_char(c)
    }
  }
  result.to_string()
}

///|
/// Const 用の型変換（GLenum, GLint などは全て Int）
fn const_type_to_moonbit(idl_type : IdlType) -> String {
  match idl_type {
    Primitive(name) =>
      match name {
        "boolean" => "Bool"
        "byte"
        | "octet"
        | "short"
        | "unsigned short"
        | "long"
        | "unsigned long" => "Int"
        "long long" | "unsigned long long" => "Int64"
        "float" | "unrestricted float" | "double" | "unrestricted double" =>
          "Double"
        _ => "Int" // 未知のプリミティブは Int
      }
    String => "String"
    Named(_) => "Int" // GLenum, GLint など WebGL 型は全て Int
    _ => "Int"
  }
}

///|
/// 定数値のフォーマット
fn format_const_value(value : String, moonbit_type : String) -> String {
  // 空文字列チェック
  if is_empty_string(value) {
    return "0"
  }

  // 文字列型の場合は引用符を追加
  if moonbit_type == "String" {
    let result = StringBuilder::new()
    result.write_string("\"")
    result.write_string(value)
    result.write_string("\"")
    return result.to_string()
  }

  // Bool型の場合
  if moonbit_type == "Bool" {
    if value == "true" || value == "1" {
      return "true"
    } else {
      return "false"
    }
  }

  // 16進数の場合、MoonBit形式に変換（0x → 0x）
  // JSの16進数はそのままMoonBitでも使える
  value
}

///|
/// Constructor から extern js fn を生成
pub fn gen_constructor(
  interface_name : String,
  ctor : ConstructorDef,
  enum_map : Array[(String, Array[String])],
) -> String {
  let return_type = interface_name

  // 引数リスト生成
  let args = StringBuilder::new()
  let args_len = ctor.arguments.length()
  for i = 0; i < args_len; i = i + 1 {
    let arg = ctor.arguments[i]
    if i > 0 {
      args.write_string(", ")
    }
    // 引数名も予約語をエスケープ
    args.write_string(escape_reserved(to_snake_case(arg.name)))
    args.write_string(" : ")
    args.write_string(idl_type_to_moonbit(arg.idl_type))
  }

  // JS呼び出しコード生成
  let js_call_args = StringBuilder::new()
  for i = 0; i < args_len; i = i + 1 {
    let arg = ctor.arguments[i]
    if i > 0 {
      js_call_args.write_string(", ")
    }
    let arg_name = escape_reserved(to_snake_case(arg.name))
    // 引数の型が enum かチェック
    match arg.idl_type {
      Named(type_name) =>
        match get_enum_values(enum_map, type_name) {
          Some(values) => {
            // enum は配列ルックアップで文字列に変換
            js_call_args.write_string("[")
            for j = 0; j < values.length(); j = j + 1 {
              if j > 0 {
                js_call_args.write_string(", ")
              }
              js_call_args.write_string("'")
              js_call_args.write_string(values[j])
              js_call_args.write_string("'")
            }
            js_call_args.write_string("][")
            js_call_args.write_string(arg_name)
            js_call_args.write_string("]")
          }
          None => js_call_args.write_string(arg_name)
        }
      Nullable(Named(type_name)) =>
        match get_enum_values(enum_map, type_name) {
          Some(values) => {
            // nullable enum も配列ルックアップ（null チェック付き）
            js_call_args.write_string("(")
            js_call_args.write_string(arg_name)
            js_call_args.write_string(" != null ? [")
            for j = 0; j < values.length(); j = j + 1 {
              if j > 0 {
                js_call_args.write_string(", ")
              }
              js_call_args.write_string("'")
              js_call_args.write_string(values[j])
              js_call_args.write_string("'")
            }
            js_call_args.write_string("][")
            js_call_args.write_string(arg_name)
            js_call_args.write_string("] : null)")
          }
          None => js_call_args.write_string(arg_name)
        }
      _ => js_call_args.write_string(arg_name)
    }
  }
  let result = StringBuilder::new()
  result.write_string("pub extern \"js\" fn ")
  result.write_string(interface_name)
  result.write_string("::new(")
  result.write_string(args.to_string())
  result.write_string(") -> ")
  result.write_string(return_type)
  result.write_string(" =\n")
  result.write_string("  #| (")

  // JS側の引数リスト（変数名のみ）
  for i = 0; i < args_len; i = i + 1 {
    let arg = ctor.arguments[i]
    if i > 0 {
      result.write_string(", ")
    }
    result.write_string(escape_reserved(to_snake_case(arg.name)))
  }
  result.write_string(") => new ")
  result.write_string(interface_name)
  result.write_string("(")
  result.write_string(js_call_args.to_string())
  result.write_string(")\n")
  result.to_string()
}

///|
/// Interface 全体から binding コードを生成
pub fn gen_interface_binding(
  iface : InterfaceDef,
  enum_map : Array[(String, Array[String])],
) -> String {
  let result = StringBuilder::new()

  // セグメント分割マーカー（大きなファイルでの65535行制限回避）
  result.write_string("///|\n")

  // 型定義
  result.write_string("/// ")
  result.write_string(iface.name)
  result.write_string(" interface\n")
  result.write_string("pub type ")
  result.write_string(iface.name)
  result.write_string("\n\n")

  // to_js_value メソッド生成
  result.write_string("pub extern \"js\" fn ")
  result.write_string(iface.name)
  result.write_string("::to_js_value(self : ")
  result.write_string(iface.name)
  result.write_string(") -> JsValue =\n")
  result.write_string("  #| (self) => self\n\n")

  // Track generated method names to avoid duplicates
  let generated_methods : Array[String] = []
  let generated_constants : Array[String] = []
  let mut has_constructor = false

  // Group operations by name for overload handling
  let operation_groups = group_operations_by_name(iface.members)

  // メンバー生成
  let members_len = iface.members.length()
  for i = 0; i < members_len; i = i + 1 {
    let mem = iface.members[i]
    match mem {
      Operation(op) =>
        // special operation の処理
        match op.special {
          Some("getter") | Some("setter") | Some("deleter") => {
            // 名前付き special operation は通常メソッドとして生成
            if not(is_empty_op_name(op.name)) {
              let fn_name = to_snake_case(op.name)
              if not(array_contains(generated_methods, fn_name)) {
                generated_methods.push(fn_name)
                result.write_string(gen_operation(iface.name, op, enum_map))
                result.write_string("\n")
              }
            }
            // special メソッド (get/set/delete) も生成
            let special_name = match op.special {
              Some("getter") =>
                // getter は引数の型で判別
                if op.arguments.length() > 0 {
                  match op.arguments[0].idl_type {
                    Primitive(_) => "get"
                    _ => "get_named"
                  }
                } else {
                  "get"
                }
              Some("setter") => "set"
              Some("deleter") => "delete"
              _ => ""
            }
            if not(array_contains(generated_methods, special_name)) {
              generated_methods.push(special_name)
              let code = gen_special_operation(
                iface.name,
                op,
                match op.special {
                  Some(s) => s
                  None => ""
                },
              )
              if code != "" {
                result.write_string(code)
                result.write_string("\n")
              }
            }
          }
          Some("static") => {
            // static operation - handle overloads
            let base_fn_name = to_snake_case(op.name)
            if not(array_contains(generated_methods, base_fn_name)) {
              // Find all static operations with this name
              let group : Array[OperationDef] = []
              for j = 0; j < operation_groups.length(); j = j + 1 {
                let (name, ops) = operation_groups[j]
                if name == op.name {
                  for o in ops {
                    match o.special {
                      Some("static") => group.push(o)
                      _ => ()
                    }
                  }
                  break
                }
              }

              // Generate all overloads
              if group.length() > 0 {
                let code = gen_overloaded_static_operations(
                  iface.name,
                  group,
                  enum_map,
                  generated_methods,
                )
                result.write_string(code)
                result.write_string("\n")
              }
            }
          }
          _ => {
            // 通常の operation - handle both overloads and optional arguments
            let base_fn_name = to_snake_case(op.name)
            if not(array_contains(generated_methods, base_fn_name)) {
              // Find all operations with this name
              let mut group : Array[OperationDef] = []
              for j = 0; j < operation_groups.length(); j = j + 1 {
                let (name, ops) = operation_groups[j]
                if name == op.name {
                  group = ops
                  break
                }
              }

              // Generate all overloads
              let code = gen_overloaded_operations(
                iface.name,
                group,
                enum_map,
                generated_methods,
              )
              result.write_string(code)
              result.write_string("\n")
            }
          }
        }
      Attribute(attr) => {
        let getter_name = "get_" + to_snake_case(attr.name)
        if not(array_contains(generated_methods, getter_name)) {
          generated_methods.push(getter_name)
          result.write_string(gen_attribute_getter(iface.name, attr))
          result.write_string("\n")
        }
        if not(attr.is_readonly) {
          let setter_name = "set_" + to_snake_case(attr.name)
          if not(array_contains(generated_methods, setter_name)) {
            generated_methods.push(setter_name)
            let setter = gen_attribute_setter(iface.name, attr)
            if setter != "" {
              result.write_string(setter)
              result.write_string("\n")
            }
          }
        }
      }
      Constructor(ctor) =>
        // 最初のコンストラクタのみ生成（overload は無視）
        if not(has_constructor) {
          has_constructor = true
          result.write_string(gen_constructor(iface.name, ctor, enum_map))
          result.write_string("\n")
        }
      Const(const_def) => {
        let interface_prefix = to_snake_case(iface.name)
        let const_suffix = const_name_to_snake_case(const_def.name)
        let const_name = interface_prefix + "_" + const_suffix
        if not(array_contains(generated_constants, const_name)) {
          generated_constants.push(const_name)
          result.write_string(gen_const(iface.name, const_def))
          result.write_string("\n")
        }
      }
      Maplike(maplike) => {
        // maplike: get, has, and if not readonly: set, delete, clear
        let code = gen_maplike_methods(iface.name, maplike, generated_methods)
        result.write_string(code)
      }
      Setlike(setlike) => {
        // setlike: has, and if not readonly: add, delete, clear
        let code = gen_setlike_methods(iface.name, setlike, generated_methods)
        result.write_string(code)
      }
    }
  }
  result.to_string()
}

///|
/// Maplike のメソッドを生成
fn gen_maplike_methods(
  interface_name : String,
  maplike : MaplikeDef,
  generated_methods : Array[String],
) -> String {
  let result = StringBuilder::new()
  let key_type = idl_type_to_moonbit(maplike.key_type)
  let value_type = idl_type_to_moonbit(maplike.value_type)

  // get(key) -> value?
  if not(array_contains(generated_methods, "get")) {
    generated_methods.push("get")
    result.write_string("pub extern \"js\" fn ")
    result.write_string(interface_name)
    result.write_string("::get(self : ")
    result.write_string(interface_name)
    result.write_string(", key : ")
    result.write_string(key_type)
    result.write_string(") -> ")
    result.write_string(value_type)
    result.write_string("? =\n")
    result.write_string("  #| (self, key) => self.get(key)\n\n")
  }

  // has(key) -> Bool
  if not(array_contains(generated_methods, "has")) {
    generated_methods.push("has")
    result.write_string("pub extern \"js\" fn ")
    result.write_string(interface_name)
    result.write_string("::has(self : ")
    result.write_string(interface_name)
    result.write_string(", key : ")
    result.write_string(key_type)
    result.write_string(") -> Bool =\n")
    result.write_string("  #| (self, key) => self.has(key)\n\n")
  }

  // If not readonly, add set/delete/clear
  if not(maplike.is_readonly) {
    // set(key, value) -> Unit
    if not(array_contains(generated_methods, "set")) {
      generated_methods.push("set")
      result.write_string("pub extern \"js\" fn ")
      result.write_string(interface_name)
      result.write_string("::set(self : ")
      result.write_string(interface_name)
      result.write_string(", key : ")
      result.write_string(key_type)
      result.write_string(", value : ")
      result.write_string(value_type)
      result.write_string(") -> Unit =\n")
      result.write_string(
        "  #| (self, key, value) => { self.set(key, value) }\n\n",
      )
    }

    // delete(key) -> Bool
    if not(array_contains(generated_methods, "delete")) {
      generated_methods.push("delete")
      result.write_string("pub extern \"js\" fn ")
      result.write_string(interface_name)
      result.write_string("::delete(self : ")
      result.write_string(interface_name)
      result.write_string(", key : ")
      result.write_string(key_type)
      result.write_string(") -> Bool =\n")
      result.write_string("  #| (self, key) => self.delete(key)\n\n")
    }

    // clear() -> Unit
    if not(array_contains(generated_methods, "clear")) {
      generated_methods.push("clear")
      result.write_string("pub extern \"js\" fn ")
      result.write_string(interface_name)
      result.write_string("::clear(self : ")
      result.write_string(interface_name)
      result.write_string(") -> Unit =\n")
      result.write_string("  #| (self) => { self.clear() }\n\n")
    }
  }
  result.to_string()
}

///|
/// Setlike のメソッドを生成
fn gen_setlike_methods(
  interface_name : String,
  setlike : SetlikeDef,
  generated_methods : Array[String],
) -> String {
  let result = StringBuilder::new()
  let value_type = idl_type_to_moonbit(setlike.value_type)

  // has(value) -> Bool
  if not(array_contains(generated_methods, "has")) {
    generated_methods.push("has")
    result.write_string("pub extern \"js\" fn ")
    result.write_string(interface_name)
    result.write_string("::has(self : ")
    result.write_string(interface_name)
    result.write_string(", value : ")
    result.write_string(value_type)
    result.write_string(") -> Bool =\n")
    result.write_string("  #| (self, value) => self.has(value)\n\n")
  }

  // If not readonly, add add/delete/clear
  if not(setlike.is_readonly) {
    // add(value) -> Unit
    if not(array_contains(generated_methods, "add")) {
      generated_methods.push("add")
      result.write_string("pub extern \"js\" fn ")
      result.write_string(interface_name)
      result.write_string("::add(self : ")
      result.write_string(interface_name)
      result.write_string(", value : ")
      result.write_string(value_type)
      result.write_string(") -> Unit =\n")
      result.write_string("  #| (self, value) => { self.add(value) }\n\n")
    }

    // delete(value) -> Bool
    if not(array_contains(generated_methods, "delete")) {
      generated_methods.push("delete")
      result.write_string("pub extern \"js\" fn ")
      result.write_string(interface_name)
      result.write_string("::delete(self : ")
      result.write_string(interface_name)
      result.write_string(", value : ")
      result.write_string(value_type)
      result.write_string(") -> Bool =\n")
      result.write_string("  #| (self, value) => self.delete(value)\n\n")
    }

    // clear() -> Unit
    if not(array_contains(generated_methods, "clear")) {
      generated_methods.push("clear")
      result.write_string("pub extern \"js\" fn ")
      result.write_string(interface_name)
      result.write_string("::clear(self : ")
      result.write_string(interface_name)
      result.write_string(") -> Unit =\n")
      result.write_string("  #| (self) => { self.clear() }\n\n")
    }
  }
  result.to_string()
}
