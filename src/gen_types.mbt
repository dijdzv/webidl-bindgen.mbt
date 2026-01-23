// Dictionary/Enum binding 生成ロジック

///|
/// Dictionary から MoonBit struct を生成
pub fn gen_dictionary(
  dict : DictionaryDef,
  enum_map : Array[(String, Array[String])],
  union_set : Array[String],
) -> String {
  let mut result = ""

  // セグメント分割マーカー（大きなファイルでの65535行制限回避）
  result = result + "///|\n"

  // ドキュメントコメント
  result = result + "/// "
  result = result + dict.name
  result = result + " dictionary\n"

  // struct 定義
  result = result + "pub struct "
  result = result + dict.name
  result = result + " {\n"
  result = dict.members.iter().fold(init=result, fn(acc, mem) {
    let moonbit_type = mem.idl_type.to_moonbit_simple()
    // オプショナルフィールド対応
    let type_str = if not(mem.required) {
      // 二重 nullable の場合（型がすでに ? で終わる）は Nullable[T] に変換
      if ends_with_question(moonbit_type) {
        let base_type = remove_trailing_question(moonbit_type)
        "Nullable[" + base_type + "]"
      } else {
        moonbit_type + "?"
      }
    } else {
      moonbit_type
    }
    acc + "  " + field_name_to_moonbit(mem.name) + " : " + type_str + "\n"
  })
  result = result + "}\n\n"

  // デフォルトコンストラクタ生成
  result = result + "/// Create a new "
  result = result + dict.name
  result = result + " with default values\n"
  result = result + "pub fn "
  result = result + dict.name
  result = result + "::default() -> "
  result = result + dict.name
  result = result + " {\n"
  // Use TypeName::{} syntax to disambiguate from map literal
  result = result + "  "
  result = result + dict.name
  result = result + "::{\n"
  result = dict.members.iter().fold(init=result, fn(acc, mem) {
    let value = if not(mem.required) {
      // Nullable[T] 型の場合は Nullable::Undefined を使用
      let moonbit_type = mem.idl_type.to_moonbit_simple()
      if ends_with_question(moonbit_type) { "Nullable::Undefined" } else { "None" }
    } else {
      // デフォルト値があれば使用
      match mem.default_value {
        Some(v) => v
        None => {
          // 型に応じたデフォルト値
          // Note: Named型には適切なデフォルト値がないため
          // この dictionary は required フィールドのデフォルト生成をスキップ
          match mem.idl_type {
            Primitive("boolean") => "false"
            Primitive(_) => "0"
            String => "\"\""
            Nullable(_) => "None"
            Void => "()"
            Sequence(_) => "[]" // 空配列
            Named(_) | Any | Promise(_) | Union(_) =>
              // デフォルトコンストラクタでは扱えないので、
              // @json.from_json などで初期化する必要がある
              "panic()"
          }
        }
      }
    }
    acc + "    " + field_name_to_moonbit(mem.name) + ": " + value + ",\n"
  })
  result = result + "  }\n"
  result = result + "}\n\n"

  // JsValue への変換関数
  result = result + "/// Convert to JsValue\n"
  result = result + "pub extern \"js\" fn "
  result = result + dict.name
  result = result + "::to_js(self : "
  result = result + dict.name
  result = result + ") -> JsValue =\n"
  result = result + "  #| (self) => ({\n"
  let members_len = dict.members.length()
  result = dict.members.iter().fold(init=(result, 0), fn(state, mem) {
    let (acc, idx) = state
    let moonbit_name = field_name_to_moonbit(mem.name)
    // Nullable[T] 型のフィールドかチェック
    let moonbit_type = mem.idl_type.to_moonbit_simple()
    let is_nullable_type = not(mem.required) && ends_with_question(moonbit_type)
    let value_expr = if is_nullable_type {
      // Nullable[T] フィールドの場合は特別な JS 式を生成
      gen_nullable_type_field_expr(mem.idl_type, moonbit_name, enum_map, union_set)
    } else {
      // 通常のフィールド（enum 変換を含む）
      gen_field_value_expr(mem.idl_type, moonbit_name, enum_map, union_set)
    }
    let comma = if idx < members_len - 1 { "," } else { "" }
    (acc + "  #|   " + mem.name + ": " + value_expr + comma + "\n", idx + 1)
  }).0
  result = result + "  #| })\n\n"
  result
}

///|
/// フィールドの値式を生成（enum の場合は配列ルックアップ、Union は .to_js_value()）
fn gen_field_value_expr(
  idl_type : IdlType,
  field_name : String,
  enum_map : Array[(String, Array[String])],
  union_set : Array[String],
) -> String {
  match idl_type {
    // 非 nullable Named フィールド（enum または Union）
    Named(type_name) =>
      match lookup_enum(enum_map, type_name) {
        Some(values) => gen_enum_lookup(field_name, values)
        None =>
          // Union 型の場合は .to_js_value() を呼ぶ
          if is_in_union_set(union_set, type_name) {
            "self." + field_name + ".to_js_value()"
          } else {
            "self." + field_name
          }
      }
    // nullable Named フィールド（enum または Union）
    Nullable(Named(type_name)) =>
      match lookup_enum(enum_map, type_name) {
        Some(values) => gen_nullable_enum_lookup(field_name, values)
        None =>
          // Nullable Union 型の場合は特別処理
          if is_in_union_set(union_set, type_name) {
            gen_nullable_union_expr(field_name)
          } else {
            "self." + field_name
          }
      }
    // 二重 nullable（Nullable[T] 型）
    Nullable(Nullable(inner)) =>
      gen_nullable_field_expr(field_name, inner, enum_map, union_set)
    // その他はそのまま
    _ => "self." + field_name
  }
}

///|
/// Union 型セットに含まれるかを判定
fn is_in_union_set(union_set : Array[String], type_name : String) -> Bool {
  union_set.contains(type_name)
}

///|
/// Nullable Union 型用の JS 式を生成（null チェック + to_js_value）
fn gen_nullable_union_expr(field_name : String) -> String {
  let result = StringBuilder::new()
  result.write_string("(self.")
  result.write_string(field_name)
  result.write_string(" != null ? self.")
  result.write_string(field_name)
  result.write_string(".to_js_value() : null)")
  result.to_string()
}

///|
/// Nullable[T] 型フィールドの JS 式を生成
fn gen_nullable_field_expr(
  field_name : String,
  inner_type : IdlType,
  enum_map : Array[(String, Array[String])],
  union_set : Array[String],
) -> String {
  let result = StringBuilder::new()
  result.write_string("((() => { const v = self.")
  result.write_string(field_name)
  result.write_string("; if (v.$tag === 0) return undefined; if (v.$tag === 1) return null; return ")

  // 内部型が enum または Union の場合は変換が必要
  match inner_type {
    Named(type_name) =>
      match lookup_enum(enum_map, type_name) {
        Some(values) => {
          result.write_string("[")
          ignore(
            values.iter().fold(init=true, fn(first, v) {
              if not(first) {
                result.write_string(", ")
              }
              result.write_string("'")
              result.write_string(v)
              result.write_string("'")
              false
            }),
          )
          result.write_string("][v.$0]")
        }
        None =>
          // Union 型の場合は .to_js_value() を呼ぶ
          if is_in_union_set(union_set, type_name) {
            result.write_string("v.$0.to_js_value()")
          } else {
            result.write_string("v.$0")
          }
      }
    _ => result.write_string("v.$0")
  }

  result.write_string("; })())")
  result.to_string()
}

///|
/// Nullable[T] 型フィールド用の JS 式を生成（optional + nullable の組み合わせ）
/// IdlType が Nullable(inner) で、かつ required=false のフィールド用
fn gen_nullable_type_field_expr(
  idl_type : IdlType,
  field_name : String,
  enum_map : Array[(String, Array[String])],
  union_set : Array[String],
) -> String {
  // IdlType は Nullable(inner) であるはず
  let inner_type = match idl_type {
    Nullable(inner) => inner
    _ => idl_type // フォールバック
  }

  let result = StringBuilder::new()
  result.write_string("((() => { const v = self.")
  result.write_string(field_name)
  result.write_string("; if (v.$tag === 0) return undefined; if (v.$tag === 1) return null; ")

  // 内部型が enum または Union の場合は変換が必要
  match inner_type {
    Named(type_name) =>
      match lookup_enum(enum_map, type_name) {
        Some(values) => {
          result.write_string("return [")
          ignore(
            values.iter().fold(init=true, fn(first, v) {
              if not(first) {
                result.write_string(", ")
              }
              result.write_string("'")
              result.write_string(v)
              result.write_string("'")
              false
            }),
          )
          result.write_string("][v.$0];")
        }
        None =>
          // Union 型の場合は .to_js_value() を呼ぶ
          if is_in_union_set(union_set, type_name) {
            result.write_string("return v.$0.to_js_value();")
          } else {
            result.write_string("return v.$0;")
          }
      }
    _ => result.write_string("return v.$0;")
  }

  result.write_string(" })())")
  result.to_string()
}

///|
/// 非 nullable enum 用の配列ルックアップ式を生成
fn gen_enum_lookup(field_name : String, values : Array[String]) -> String {
  gen_enum_array_lookup(values, "self." + field_name)
}

///|
/// nullable enum 用の配列ルックアップ式を生成（null チェック付き）
fn gen_nullable_enum_lookup(field_name : String, values : Array[String]) -> String {
  gen_nullable_enum_array_lookup(values, "self." + field_name)
}

///|
/// Enum から MoonBit enum を生成
pub fn gen_enum(enum_def : EnumDef) -> String {
  let mut result = ""

  // セグメント分割マーカー
  result = result + "///|\n"

  // ドキュメントコメント
  result = result + "/// "
  result = result + enum_def.name
  result = result + " enum\n"

  // enum 定義
  result = result + "pub(all) enum "
  result = result + enum_def.name
  result = result + " {\n"
  result = enum_def.values.iter().fold(init=result, fn(acc, value) {
    // 値をPascalCaseに変換
    let variant = to_pascal_case(value)
    acc + "  " + variant + "\n"
  })
  result = result + "}\n\n"

  // 文字列への変換関数
  result = result + "/// Convert to string value\n"
  result = result + "pub fn "
  result = result + enum_def.name
  result = result + "::to_string(self : "
  result = result + enum_def.name
  result = result + ") -> String {\n"
  result = result + "  match self {\n"
  result = enum_def.values.iter().fold(init=result, fn(acc, value) {
    let variant = to_pascal_case(value)
    acc + "    " + enum_def.name + "::" + variant + " => \"" + value + "\"\n"
  })
  result = result + "  }\n"
  result = result + "}\n\n"

  // 文字列からの変換関数
  result = result + "/// Parse from string value\n"
  result = result + "pub fn "
  result = result + enum_def.name
  result = result + "::from_string(s : String) -> "
  result = result + enum_def.name
  result = result + "? {\n"
  result = result + "  match s {\n"
  result = enum_def.values.iter().fold(init=result, fn(acc, value) {
    let variant = to_pascal_case(value)
    acc + "    \"" + value + "\" => Some(" + enum_def.name + "::" + variant + ")\n"
  })
  result = result + "    _ => None\n"
  result = result + "  }\n"
  result = result + "}\n"
  result
}


///|
/// フィールド名を MoonBit 用に変換（小文字開始、ハイフンをアンダースコアに）
fn field_name_to_moonbit(name : String) -> String {
  let result = StringBuilder::new()
  ignore(
    name.iter().fold(init=true, fn(first, c) {
      if first {
        // 最初の文字は小文字に
        if c >= 'A' && c <= 'Z' {
          result.write_char((c.to_int() + 32).unsafe_to_char())
        } else {
          result.write_char(c)
        }
      } else if c == '-' {
        result.write_char('_')
      } else {
        result.write_char(c)
      }
      false
    }),
  )
  escape_reserved(result.to_string())
}

///|
/// MoonBit プリミティブ型名と衝突するかチェック
fn is_primitive_type_name(name : String) -> Bool {
  // MoonBit の組み込み型名
  match name {
    "String" | "Bool" | "Int" | "Int64" | "Double" | "Unit" | "Bytes" | "Array" | "Char" => true
    _ => false
  }
}

///|
/// Typedef から MoonBit type alias を生成
/// dictionary_names: Dictionary型の名前リスト（is_*/as_*の型チェックで使用）
/// union_typedef_map: Union typedef名から構成要素へのマップ
/// enum_names: enum型の名前リスト（instanceof -> typeof === 'string'）
/// primitive_typedef_map: プリミティブtypedef名から解決後の型へのマップ
/// callback_interface_names: callback interface型の名前リスト（instanceof -> typeof === 'function'）
pub fn gen_typedef(
  typedef_def : TypedefDef,
  dictionary_names~ : Array[String] = [],
  union_typedef_map~ : Array[(String, Array[IdlType])] = [],
  enum_names~ : Array[String] = [],
  primitive_typedef_map~ : Array[(String, IdlType)] = [],
  callback_interface_names~ : Array[String] = [],
) -> String {
  // プリミティブ型名との衝突を避ける
  if is_primitive_type_name(typedef_def.name) {
    return ""
  }

  // 1メンバーの Union はスキップ（その型を直接使うべき）
  match typedef_def.idl_type {
    Union(members) =>
      if members.length() == 1 {
        return ""
      }
    _ => ()
  }

  let mut result = ""

  // セグメント分割マーカー
  result = result + "///|\n"

  // ドキュメントコメント
  result = result + "/// "
  result = result + typedef_def.name
  result = result + " typedef\n"

  // Union 型の場合は opaque 型として定義（型安全なファクトリ関数のため）
  match typedef_def.idl_type {
    Union(members) => {
      // Opaque 型定義（JsValue エイリアスではない独立した型）
      result = result + "pub type "
      result = result + typedef_def.name
      result = result + "\n\n"

      // to_js_value メソッド（JS に渡すため）
      result = result + "pub extern \"js\" fn "
      result = result + typedef_def.name
      result = result + "::to_js_value(self : "
      result = result + typedef_def.name
      result = result + ") -> JsValue =\n  #| (self) => self\n\n"

      // ファクトリ関数（各メンバー型から Union 型を作成）
      result = members.iter().fold(init=result, fn(acc, mem) {
        let factory = gen_union_factory(typedef_def.name, mem)
        if factory != "" { acc + factory } else { acc }
      })

      // is_* チェック関数（Union の中身を判定）
      result = members.iter().fold(init=result, fn(acc, mem) {
        let is_check = gen_union_is_check(
          typedef_def.name,
          mem,
          dictionary_names,
          union_typedef_map~,
          enum_names~,
          primitive_typedef_map~,
          callback_interface_names~,
        )
        if is_check != "" { acc + is_check } else { acc }
      })

      // as_* 変換関数（Union から具体型を取得）
      result = members.iter().fold(init=result, fn(acc, mem) {
        let as_cast = gen_union_as_cast(
          typedef_def.name,
          mem,
          dictionary_names,
          union_typedef_map~,
          enum_names~,
          primitive_typedef_map~,
          callback_interface_names~,
        )
        if as_cast != "" { acc + as_cast } else { acc }
      })
    }
    _ => {
      // 非 Union 型は従来通り type alias
      result = result + "pub type "
      result = result + typedef_def.name
      result = result + " = "
      result = result + typedef_def.idl_type.to_moonbit_simple()
      result = result + "\n"
    }
  }

  result
}

///|
/// Union 型のファクトリ関数を生成
fn gen_union_factory(union_name : String, member_type : IdlType) -> String {
  let moonbit_type = member_type.to_moonbit_simple()
  let factory_name = get_factory_name(member_type)

  // JsValue 型はスキップ（Any, Union 内 Union などの場合）
  if moonbit_type == "JsValue" || factory_name == "" {
    return ""
  }

  let result = StringBuilder::new()
  result.write_string("/// Create ")
  result.write_string(union_name)
  result.write_string(" from ")
  result.write_string(moonbit_type)
  result.write_string("\n")
  result.write_string("pub extern \"js\" fn ")
  result.write_string(union_name)
  result.write_string("::from_")
  result.write_string(factory_name)
  result.write_string("(v : ")
  result.write_string(moonbit_type)
  result.write_string(") -> ")
  result.write_string(union_name)
  result.write_string(" =\n  #| (v) => v\n\n")
  result.to_string()
}

///|
/// IdlType からファクトリ関数名を取得
fn get_factory_name(idl_type : IdlType) -> String {
  match idl_type {
    Primitive(name) =>
      match name {
        "DOMString" | "USVString" | "ByteString" => "string"
        "boolean" => "bool"
        "byte" | "octet" | "short" | "unsigned short" | "long" | "unsigned long" =>
          "int"
        "long long" | "unsigned long long" => "int64"
        "float" | "unrestricted float" | "double" | "unrestricted double" =>
          "double"
        _ => ""
      }
    String => "string"
    Named(name) => to_snake_case_factory(name)
    Sequence(inner) => {
      let inner_name = get_factory_name(inner)
      if inner_name != "" {
        "array_of_" + inner_name
      } else {
        "array"
      }
    }
    Nullable(inner) => {
      let inner_name = get_factory_name(inner)
      if inner_name != "" {
        "nullable_" + inner_name
      } else {
        ""
      }
    }
    // Void, Any, Promise, Union はファクトリを生成しない
    _ => ""
  }
}

///|
/// 型名を snake_case に変換（ファクトリ関数名用）
fn to_snake_case_factory(name : String) -> String {
  let result = StringBuilder::new()
  ignore(
    name.iter().fold(init=true, fn(first, c) {
      if c >= 'A' && c <= 'Z' {
        if not(first) {
          result.write_char('_')
        }
        // 大文字を小文字に変換
        result.write_char((c.to_int() + 32).unsafe_to_char())
      } else {
        result.write_char(c)
      }
      false
    }),
  )
  result.to_string()
}

///|
/// Union 型の is_* チェック関数を生成
fn gen_union_is_check(
  union_name : String,
  member_type : IdlType,
  dictionary_names : Array[String],
  union_typedef_map~ : Array[(String, Array[IdlType])] = [],
  enum_names~ : Array[String] = [],
  primitive_typedef_map~ : Array[(String, IdlType)] = [],
  callback_interface_names~ : Array[String] = [],
) -> String {
  let moonbit_type = member_type.to_moonbit_simple()
  let factory_name = get_factory_name(member_type)
  let js_check = get_js_type_check(member_type, dictionary_names, union_typedef_map~, enum_names~, primitive_typedef_map~, callback_interface_names~)

  // JsValue 型やチェックできない型はスキップ
  if moonbit_type == "JsValue" || factory_name == "" || js_check == "" {
    return ""
  }

  let result = StringBuilder::new()
  result.write_string("/// Check if this ")
  result.write_string(union_name)
  result.write_string(" is ")
  result.write_string(moonbit_type)
  result.write_string("\n")
  result.write_string("pub extern \"js\" fn ")
  result.write_string(union_name)
  result.write_string("::is_")
  result.write_string(factory_name)
  result.write_string("(self : ")
  result.write_string(union_name)
  result.write_string(") -> Bool =\n  #| (self) => ")
  result.write_string(js_check)
  result.write_string("\n\n")
  result.to_string()
}

///|
/// Union 型の as_* 変換関数を生成
fn gen_union_as_cast(
  union_name : String,
  member_type : IdlType,
  dictionary_names : Array[String],
  union_typedef_map~ : Array[(String, Array[IdlType])] = [],
  enum_names~ : Array[String] = [],
  primitive_typedef_map~ : Array[(String, IdlType)] = [],
  callback_interface_names~ : Array[String] = [],
) -> String {
  let moonbit_type = member_type.to_moonbit_simple()
  let factory_name = get_factory_name(member_type)
  let js_check = get_js_type_check(member_type, dictionary_names, union_typedef_map~, enum_names~, primitive_typedef_map~, callback_interface_names~)

  // JsValue 型やチェックできない型はスキップ
  if moonbit_type == "JsValue" || factory_name == "" || js_check == "" {
    return ""
  }

  let result = StringBuilder::new()
  result.write_string("/// Try to get ")
  result.write_string(union_name)
  result.write_string(" as ")
  result.write_string(moonbit_type)
  result.write_string("\n")
  result.write_string("pub extern \"js\" fn ")
  result.write_string(union_name)
  result.write_string("::as_")
  result.write_string(factory_name)
  result.write_string("(self : ")
  result.write_string(union_name)
  result.write_string(") -> ")
  result.write_string(moonbit_type)
  result.write_string("? =\n  #| (self) => (")
  result.write_string(js_check)
  result.write_string(") ? { $tag: 1, _0: self } : { $tag: 0 }\n\n")
  result.to_string()
}

///|
/// IdlType から JS の型チェックコードを取得
/// dictionary_names: Dictionary型の名前リスト（instanceofではなくtypeofを使う）
/// union_typedef_map: Union typedef名から構成要素へのマップ
/// enum_names: enum型の名前リスト（instanceof -> typeof === 'string'）
/// primitive_typedef_map: プリミティブtypedef名から解決後の型へのマップ
/// callback_interface_names: callback interface型の名前リスト（instanceof -> typeof === 'function'）
fn get_js_type_check(
  idl_type : IdlType,
  dictionary_names : Array[String],
  union_typedef_map~ : Array[(String, Array[IdlType])] = [],
  enum_names~ : Array[String] = [],
  primitive_typedef_map~ : Array[(String, IdlType)] = [],
  callback_interface_names~ : Array[String] = [],
) -> String {
  match idl_type {
    Primitive(name) =>
      match name {
        "DOMString" | "USVString" | "ByteString" => "typeof self === 'string'"
        "boolean" => "typeof self === 'boolean'"
        "byte" | "octet" | "short" | "unsigned short" | "long" | "unsigned long" |
        "long long" | "unsigned long long" | "float" | "unrestricted float" |
        "double" | "unrestricted double" => "typeof self === 'number'"
        _ => ""
      }
    String => "typeof self === 'string'"
    Named(name) => {
      // 特殊な外部型を処理（WebIDL specs に定義がない型）
      // CSSOMString は CSSOM で typedef DOMString CSSOMString として定義
      if name == "CSSOMString" {
        return "typeof self === 'string'"
      }
      // WindowProxy は HTML spec の特殊な型（window オブジェクトを表す）
      // JS にコンストラクタがないので、window かどうかを typeof でチェック
      if name == "WindowProxy" {
        return "typeof self === 'object' && self !== null && self.window === self"
      }
      // callback interface型はJSでは関数なのでtypeof === 'function'を使う
      if callback_interface_names.contains(name) {
        return "typeof self === 'function'"
      }
      // enum型はJSでは文字列なのでtypeof === 'string'を使う
      if enum_names.contains(name) {
        return "typeof self === 'string'"
      }
      // プリミティブtypedefは解決後の型でチェック
      let primitive_check = primitive_typedef_map.iter().fold(
        init=(None : String?),
        fn(found, entry) {
          match found {
            Some(_) => found
            None => {
              let (typedef_name, resolved_type) = entry
              if typedef_name == name {
                Some(
                  get_js_type_check(
                    resolved_type,
                    dictionary_names,
                    union_typedef_map~,
                    enum_names~,
                    primitive_typedef_map~,
                    callback_interface_names~,
                  ),
                )
              } else {
                None
              }
            }
          }
        },
      )
      match primitive_check {
        Some(check) => return check
        None => ()
      }
      // Dictionary型はinstanceofが使えないのでtypeofでオブジェクトチェック
      if dictionary_names.contains(name) {
        return "typeof self === 'object' && self !== null"
      }
      // Union typedef はJSにクラスが存在しないので構成要素を展開
      let union_check = union_typedef_map.iter().fold(
        init=(None : String?),
        fn(found, entry) {
          match found {
            Some(_) => found
            None => {
              let (typedef_name, members) = entry
              if typedef_name == name {
                // 構成要素それぞれのチェックを OR で結合
                let checks = members.iter().filter_map(fn(mem) {
                  let check = get_js_type_check(
                    mem,
                    dictionary_names,
                    union_typedef_map~,
                    enum_names~,
                    primitive_typedef_map~,
                    callback_interface_names~,
                  )
                  if check != "" { Some(check) } else { None }
                }).collect()
                if checks.length() > 0 {
                  Some(checks.iter().collect().join(" || "))
                } else {
                  // チェックできない場合は常にtrue（型安全性を犠牲にする）
                  Some("true")
                }
              } else {
                None
              }
            }
          }
        },
      )
      match union_check {
        Some(check) => return check
        None => ()
      }
      // 通常のInterface型
      "self instanceof " + name
    }
    Sequence(_) => "Array.isArray(self)"
    Nullable(inner) => {
      // null チェックは特殊: null または inner の型
      let inner_check = get_js_type_check(
        inner,
        dictionary_names,
        union_typedef_map~,
        enum_names~,
        primitive_typedef_map~,
        callback_interface_names~,
      )
      if inner_check != "" {
        "self === null || (" + inner_check + ")"
      } else {
        "self === null"
      }
    }
    // Void, Any, Promise, Union はチェックできない
    _ => ""
  }
}
