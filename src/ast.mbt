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
/// Callback Interface 定義（opaque型として扱う）
pub struct CallbackInterfaceDef {
  name : String
}

///|
/// Interface メンバー
pub enum InterfaceMember {
  Operation(OperationDef)
  Attribute(AttributeDef)
  Const(ConstDef)
  Constructor(ConstructorDef)
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
