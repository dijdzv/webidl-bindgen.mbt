// WebIDL AST 型定義

///|
/// WebIDL の定義全体
pub enum Definition {
  Interface(InterfaceDef)
  InterfaceMixin(InterfaceMixinDef)
  CallbackInterface(CallbackInterfaceDef)
  Dictionary(DictionaryDef)
  Enum(EnumDef)
  Typedef(TypedefDef)
  Partial(PartialDef)
  Includes(IncludesDef)
}

///|
/// Includes ステートメント（インターフェースがmixinを含む）
pub struct IncludesDef {
  target : String // mixin を受け取るインターフェース名
  includes : String // mixin 名
}

///|
/// Interface 定義
pub struct InterfaceDef {
  name : String
  members : Array[InterfaceMember]
  inheritance : String? // 継承元
  extended_attrs : Array[ExtendedAttribute]
}

///|
/// Interface Mixin 定義
pub struct InterfaceMixinDef {
  name : String
  members : Array[InterfaceMember]
}

///|
/// Callback Interface 定義
/// callback interface EventListener { void handleEvent(Event event); }
/// または callback FrameRequestCallback = void (DOMHighResTimeStamp time);
pub struct CallbackInterfaceDef {
  name : String
  return_type : IdlType? // void の場合は None
  arguments : Array[Argument] // コールバックの引数
}

///|
/// Interface メンバー
pub enum InterfaceMember {
  Operation(OperationDef)
  Attribute(AttributeDef)
  Const(ConstDef)
  Constructor(ConstructorDef)
  Maplike(MaplikeDef)
  Setlike(SetlikeDef)
}

///|
/// Maplike 定義
pub struct MaplikeDef {
  key_type : IdlType
  value_type : IdlType
  is_readonly : Bool
}

///|
/// Setlike 定義
pub struct SetlikeDef {
  value_type : IdlType
  is_readonly : Bool
}

///|
/// 操作（メソッド）定義
pub struct OperationDef {
  name : String
  return_type : IdlType
  arguments : Array[Argument]
  special : String? // getter, setter, etc.
}

///|
/// 属性定義
pub struct AttributeDef {
  name : String
  idl_type : IdlType
  is_readonly : Bool
}

///|
/// 引数定義
pub struct Argument {
  name : String
  idl_type : IdlType
  optional : Bool
  default_value : String?
}

///|
/// コンストラクタ定義
pub struct ConstructorDef {
  arguments : Array[Argument]
}

///|
/// 定数定義
pub struct ConstDef {
  name : String
  idl_type : IdlType
  value : String
}

///|
/// Dictionary 定義
pub struct DictionaryDef {
  name : String
  members : Array[DictionaryMember]
  inheritance : String?
}

///|
/// Dictionary メンバー
pub struct DictionaryMember {
  name : String
  idl_type : IdlType
  required : Bool
  default_value : String?
}

///|
/// Enum 定義
pub struct EnumDef {
  name : String
  values : Array[String]
}

///|
/// Typedef 定義
pub struct TypedefDef {
  name : String
  idl_type : IdlType
}

///|
/// Partial 定義
pub struct PartialDef {
  target : String // interface or dictionary name
  members : Array[InterfaceMember]
}

///|
/// IDL 型
pub enum IdlType {
  Primitive(String) // "double", "boolean", "long", etc.
  String // DOMString
  Sequence(IdlType) // sequence<T>
  Promise(IdlType) // Promise<T>
  Nullable(IdlType) // T?
  Union(Array[IdlType]) // (A or B)
  Named(String) // カスタム型名
  Any
  Void // undefined
}

///|
/// 拡張属性（将来のパース実装用）
pub(all) struct ExtendedAttribute {
  name : String
  value : String?
} derive(Show)

///|
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
  entry : (String, Array[IdlType]),
) -> Unit {
  self.entries.push(entry)
}

///|
/// コレクタのイテレーション用
pub fn InlineUnionCollector::iter(
  self : InlineUnionCollector,
) -> Iter[(String, Array[IdlType])] {
  self.entries.iter()
}

///|
/// コレクタの長さ
pub fn InlineUnionCollector::length(self : InlineUnionCollector) -> Int {
  self.entries.length()
}

///|
/// WebIDL 型を MoonBit 型に変換（シンプル版、Union は JsValue）
pub fn IdlType::to_moonbit_simple(self : IdlType) -> String {
  match self {
    Primitive(name) => primitive_to_moonbit(name)
    String => "String"
    Void => "Unit"
    Nullable(inner) => {
      let inner_type = inner.to_moonbit_simple()
      // 二重 nullable の場合は Nullable[T] に変換
      if ends_with_question(inner_type) {
        // T? が来た → Nullable[T] に変換
        let base_type = remove_trailing_question(inner_type)
        "Nullable[" + base_type + "]"
      } else {
        inner_type + "?"
      }
    }
    Named(name) => {
      // 小文字始まりの型名は JsValue に変換（object など無効な型名）
      let first_char = get_first_char(name)
      if first_char >= 'a' && first_char <= 'z' {
        "JsValue"
      } else {
        name
      }
    }
    Sequence(inner) => {
      let inner_type = inner.to_moonbit_simple()
      "Array[" + inner_type + "]"
    }
    Promise(inner) => {
      let inner_type = inner.to_moonbit_simple()
      "Promise[" + inner_type + "]"
    }
    Union(_) => "JsValue"
    Any => "JsValue"
  }
}
