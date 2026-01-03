// Dependency graph analysis for sub-package generation

///|
/// 仕様をカテゴリに分類
/// カテゴリ名を返す。None の場合は個別パッケージ
pub fn assign_to_category(spec_name : String) -> String? {
  // WebGL拡張 → webgl_extensions
  if spec_name.has_prefix("ANGLE_") ||
     spec_name.has_prefix("EXT_") ||
     spec_name.has_prefix("OES_") ||
     spec_name.has_prefix("WEBGL_") ||
     spec_name.has_prefix("OVR_") ||
     spec_name.has_prefix("KHR_") {
    return Some("webgl_extensions")
  }

  // WebXR関連 → webxr
  if spec_name.has_prefix("webxr") {
    return Some("webxr")
  }

  // CSS関連 → cssom (css-*, cssom, cssom-view)
  if spec_name.has_prefix("css-") ||
     spec_name == "cssom" ||
     spec_name == "cssom-view" {
    return Some("cssom")
  }

  // WebCodecs codec registrations → webcodecs
  if spec_name.has_prefix("webcodecs-") {
    return Some("webcodecs")
  }

  // MediaCapture関連 → mediacapture
  if spec_name.has_prefix("mediacapture-") ||
     spec_name == "media-source" ||
     spec_name == "mediastream-recording" ||
     spec_name == "media-capabilities" ||
     spec_name == "media-playback-quality" {
    return Some("mediacapture")
  }

  // Sensor APIs → sensors
  if spec_name == "accelerometer" ||
     spec_name == "gyroscope" ||
     spec_name == "magnetometer" ||
     spec_name == "ambient-light" ||
     spec_name == "proximity" ||
     spec_name == "orientation-sensor" ||
     spec_name == "geolocation-sensor" ||
     spec_name == "generic-sensor" {
    return Some("sensors")
  }

  // Permissions関連 → permissions
  if spec_name.has_prefix("permissions") {
    return Some("permissions")
  }

  // Storage関連 → storage
  if spec_name == "storage" ||
     spec_name == "storage-access" ||
     spec_name == "storage-buckets" {
    return Some("storage_apis")
  }

  // Reporting関連 → reporting
  if spec_name.has_prefix("crash-") ||
     spec_name.has_prefix("deprecation-") ||
     spec_name.has_prefix("intervention-") ||
     spec_name == "reporting" {
    return Some("reporting")
  }

  // Pointer/Touch/Input → input
  if spec_name == "pointerevents" ||
     spec_name == "pointerlock" ||
     spec_name == "touch-events" ||
     spec_name == "input-events" ||
     spec_name == "input-device-capabilities" {
    return Some("input_events")
  }

  // 極小API (misc_apis に統合)
  if spec_name == "badging" ||
     spec_name == "device-memory" ||
     spec_name == "gpc" ||
     spec_name == "savedata" ||
     spec_name == "webdriver" ||
     spec_name == "beacon" ||
     spec_name == "vibration" {
    return Some("misc_apis")
  }

  // それ以外は個別パッケージ
  None
}

///|
/// カテゴリ別にグループを作成
pub fn create_category_groups(
  deps : Array[SpecDependency],
) -> (Array[PackageGroup], Array[(String, String)]) {
  // カテゴリ名 -> 含まれる仕様のマップ
  let category_specs : Array[(String, Array[String])] = []

  for dep in deps {
    match assign_to_category(dep.spec_name) {
      Some(cat) => {
        // カテゴリに追加
        let mut found = false
        for entry in category_specs {
          if entry.0 == cat {
            add_unique(entry.1, dep.spec_name)
            found = true
            break
          }
        }
        if not(found) {
          category_specs.push((cat, [dep.spec_name]))
        }
      }
      None => ()  // 個別パッケージとして後で処理
    }
  }

  // グループとマッピングを作成
  let groups : Array[PackageGroup] = []
  let mapping : Array[(String, String)] = []

  for entry in category_specs {
    let cat = entry.0
    let specs = entry.1

    // グループを作成
    groups.push(PackageGroup::{
      name: cat,
      specs: specs,
      depends_on: [],
    })

    // マッピングを記録
    for spec in specs {
      mapping.push((spec, cat))
    }
  }

  (groups, mapping)
}

///|
/// 仕様の依存情報
pub struct SpecDependency {
  spec_name : String
  depends_on : Array[String]  // この仕様が依存する他の仕様名
}

///|
/// マージされたパッケージグループ
pub struct PackageGroup {
  name : String           // グループ名 (e.g., "dom-html", "webrtc")
  specs : Array[String]   // 含まれる仕様名
  depends_on : Array[String]  // 他のグループへの依存
}

///|
/// 依存グラフを構築
/// 戻り値: (spec_name, depends_on_specs) のリスト
pub fn build_dependency_graph(
  results : Array[SpecLoadResult],
  ownership : Array[(String, String)],
) -> Array[SpecDependency] {
  let deps : Array[SpecDependency] = []

  // 型名 -> 仕様名のマップを構築
  let type_to_spec : Array[(String, String)] = []
  for entry in ownership {
    type_to_spec.push(entry)
  }

  for result in results {
    if not(result.success) {
      continue
    }

    let spec_name = result.spec_name
    let referenced_specs : Array[String] = []

    // この仕様が参照する型を収集
    let refs = collect_type_references_from_defs(result.definitions)

    // 各参照型がどの仕様で定義されているか調べる
    for ref_type in refs {
      for entry in type_to_spec {
        if entry.0 == ref_type && entry.1 != spec_name {
          // 既に追加済みでなければ追加
          let mut found = false
          for existing in referenced_specs {
            if existing == entry.1 {
              found = true
              break
            }
          }
          if not(found) {
            referenced_specs.push(entry.1)
          }
          break
        }
      }
    }

    deps.push(SpecDependency::{ spec_name, depends_on: referenced_specs })
  }

  deps
}

///|
/// 定義から参照される型名を収集
fn collect_type_references_from_defs(defs : Array[Definition]) -> Array[String] {
  let refs : Array[String] = []

  for def in defs {
    collect_type_refs_from_def(def, refs)
  }

  refs
}

///|
fn collect_type_refs_from_def(def : Definition, refs : Array[String]) -> Unit {
  match def {
    Interface(iface) => {
      // 継承
      match iface.inheritance {
        Some(parent) => add_unique(refs, parent)
        None => ()
      }
      // メンバー
      for mem in iface.members {
        collect_type_refs_from_member(mem, refs)
      }
    }
    InterfaceMixin(mix) => {
      for mem in mix.members {
        collect_type_refs_from_member(mem, refs)
      }
    }
    Dictionary(d) => {
      match d.inheritance {
        Some(parent) => add_unique(refs, parent)
        None => ()
      }
      for mem in d.members {
        collect_type_refs_from_idl_type(mem.idl_type, refs)
      }
    }
    Typedef(t) => {
      collect_type_refs_from_idl_type(t.idl_type, refs)
    }
    CallbackInterface(cb) => {
      // CallbackInterface has return_type and arguments
      match cb.return_type {
        Some(rt) => collect_type_refs_from_idl_type(rt, refs)
        None => ()
      }
      for arg in cb.arguments {
        collect_type_refs_from_idl_type(arg.idl_type, refs)
      }
    }
    Enum(_) => ()  // Enum doesn't reference other types
    Partial(p) => {
      // Partial references its target type
      add_unique(refs, p.target)
      // Also collect refs from members
      for mem in p.members {
        collect_type_refs_from_member(mem, refs)
      }
    }
    Includes(incl) => {
      // Includes references both target and mixin
      add_unique(refs, incl.target)
      add_unique(refs, incl.includes)
    }
  }
}

///|
fn collect_type_refs_from_member(mem : InterfaceMember, refs : Array[String]) -> Unit {
  match mem {
    Attribute(attr) => collect_type_refs_from_idl_type(attr.idl_type, refs)
    Operation(op) => {
      collect_type_refs_from_idl_type(op.return_type, refs)
      for arg in op.arguments {
        collect_type_refs_from_idl_type(arg.idl_type, refs)
      }
    }
    Constructor(ctor) => {
      for arg in ctor.arguments {
        collect_type_refs_from_idl_type(arg.idl_type, refs)
      }
    }
    Const(c) => collect_type_refs_from_idl_type(c.idl_type, refs)
    Maplike(m) => {
      collect_type_refs_from_idl_type(m.key_type, refs)
      collect_type_refs_from_idl_type(m.value_type, refs)
    }
    Setlike(s) => collect_type_refs_from_idl_type(s.value_type, refs)
  }
}

///|
fn collect_type_refs_from_idl_type(idl_type : IdlType, refs : Array[String]) -> Unit {
  match idl_type {
    Named(name) => {
      // 大文字で始まる型名のみ（プリミティブ除外）
      let first = get_first_char_dep(name)
      if first >= 'A' && first <= 'Z' {
        add_unique(refs, name)
      }
    }
    Nullable(inner) => collect_type_refs_from_idl_type(inner, refs)
    Sequence(inner) => collect_type_refs_from_idl_type(inner, refs)
    Promise(inner) => collect_type_refs_from_idl_type(inner, refs)
    Union(types) => {
      for t in types {
        collect_type_refs_from_idl_type(t, refs)
      }
    }
    Primitive(_) | String | Void | Any => ()
  }
}

///|
fn get_first_char_dep(s : String) -> Char {
  for c in s {
    return c
  }
  ' '
}

///|
fn add_unique(arr : Array[String], item : String) -> Unit {
  for existing in arr {
    if existing == item {
      return
    }
  }
  arr.push(item)
}

///|
/// 双方向依存を検出してグループ化
pub fn find_bidirectional_groups(deps : Array[SpecDependency]) -> Array[PackageGroup] {
  // 双方向依存の隣接リスト構築
  let bi_deps : Array[(String, Array[String])] = []

  for dep_a in deps {
    for spec_b in dep_a.depends_on {
      // spec_b が spec_a に依存しているかチェック
      for dep_b in deps {
        if dep_b.spec_name == spec_b {
          for back_dep in dep_b.depends_on {
            if back_dep == dep_a.spec_name {
              // 双方向依存を発見
              add_bi_dep(bi_deps, dep_a.spec_name, spec_b)
              add_bi_dep(bi_deps, spec_b, dep_a.spec_name)
            }
          }
          break
        }
      }
    }
  }

  // 連結成分を見つける (Union-Find的なアプローチ)
  let visited : Array[String] = []
  let groups : Array[PackageGroup] = []

  for entry in bi_deps {
    let start = entry.0

    // 既に訪問済みならスキップ
    let mut already_visited = false
    for v in visited {
      if v == start {
        already_visited = true
        break
      }
    }
    if already_visited {
      continue
    }

    // BFSで連結成分を探索
    let component : Array[String] = []
    let queue : Array[String] = [start]

    while queue.length() > 0 {
      let node = queue.remove(0)

      // 既に訪問済みならスキップ
      let mut is_visited = false
      for v in visited {
        if v == node {
          is_visited = true
          break
        }
      }
      if is_visited {
        continue
      }

      visited.push(node)
      component.push(node)

      // 隣接ノードをキューに追加
      for entry2 in bi_deps {
        if entry2.0 == node {
          for neighbor in entry2.1 {
            let mut neighbor_visited = false
            for v in visited {
              if v == neighbor {
                neighbor_visited = true
                break
              }
            }
            if not(neighbor_visited) {
              queue.push(neighbor)
            }
          }
          break
        }
      }
    }

    if component.length() > 0 {
      // グループ名を決定（最初の仕様名をベースに）
      let group_name = determine_group_name(component)
      groups.push(PackageGroup::{ name: group_name, specs: component, depends_on: [] })
    }
  }

  groups
}

///|
fn add_bi_dep(bi_deps : Array[(String, Array[String])], from : String, to : String) -> Unit {
  for entry in bi_deps {
    if entry.0 == from {
      add_unique(entry.1, to)
      return
    }
  }
  bi_deps.push((from, [to]))
}

///|
fn determine_group_name(specs : Array[String]) -> String {
  // 特定の組み合わせに名前を付ける
  let mut has_dom = false
  let mut has_html = false
  let mut has_webrtc = false
  let mut has_webcrypto = false

  for s in specs {
    if s == "dom" {
      has_dom = true
    } else if s == "html" {
      has_html = true
    } else if s == "webrtc" {
      has_webrtc = true
    } else if s == "webcrypto" {
      has_webcrypto = true
    }
  }

  if has_dom && has_html {
    return "dom_html"
  }
  if has_webrtc {
    return "webrtc"
  }
  if has_webcrypto {
    return "webcrypto"
  }

  // デフォルト: 最初の仕様名 (ハイフンをアンダースコアに変換)
  if specs.length() > 0 {
    sanitize_package_name(specs[0])
  } else {
    "unknown"
  }
}

///|
/// パッケージ名をMoonBit識別子として有効な形式に変換
/// ハイフンをアンダースコアに変換
pub fn sanitize_package_name(name : String) -> String {
  let result = StringBuilder::new()
  for c in name {
    if c == '-' {
      result.write_char('_')
    } else {
      result.write_char(c)
    }
  }
  result.to_string()
}

///|
/// 仕様がどのグループに属するかのマップを構築
pub fn build_spec_to_group_map(groups : Array[PackageGroup]) -> Array[(String, String)] {
  let mapping : Array[(String, String)] = []

  for group in groups {
    for spec in group.specs {
      mapping.push((spec, group.name))
    }
  }

  mapping
}

///|
/// グループ間の依存関係を計算
pub fn compute_group_dependencies(
  deps : Array[SpecDependency],
  groups : Array[PackageGroup],
  spec_to_group : Array[(String, String)],
) -> Unit {
  for group in groups {
    let group_deps : Array[String] = []

    // グループ内の各仕様の依存先を調べる
    for spec in group.specs {
      for dep in deps {
        if dep.spec_name == spec {
          for dep_spec in dep.depends_on {
            // 依存先がどのグループに属するか (サニタイズされた名前で)
            let mut dep_group : String = sanitize_package_name(dep_spec)
            for mapping in spec_to_group {
              if mapping.0 == dep_spec {
                dep_group = mapping.1  // Already sanitized
                break
              }
            }

            // 自分のグループでなければ追加
            if dep_group != group.name {
              add_unique(group_deps, dep_group)
            }
          }
          break
        }
      }
    }

    // group.depends_on に設定
    for d in group_deps {
      group.depends_on.push(d)
    }
  }
}

///|
/// 独立した仕様（グループに属さない）のパッケージグループを作成
pub fn create_independent_groups(
  deps : Array[SpecDependency],
  spec_to_group : Array[(String, String)],
) -> Array[PackageGroup] {
  let groups : Array[PackageGroup] = []

  for dep in deps {
    // 既にグループに属しているかチェック
    let mut in_group = false
    for mapping in spec_to_group {
      if mapping.0 == dep.spec_name {
        in_group = true
        break
      }
    }

    if not(in_group) {
      // 独立パッケージを作成
      let group_deps : Array[String] = []

      for dep_spec in dep.depends_on {
        // 依存先のグループ名を解決
        let mut resolved = sanitize_package_name(dep_spec)
        for mapping in spec_to_group {
          if mapping.0 == dep_spec {
            resolved = mapping.1  // Already sanitized when group was created
            break
          }
        }
        add_unique(group_deps, resolved)
      }

      groups.push(PackageGroup::{
        name: sanitize_package_name(dep.spec_name),
        specs: [dep.spec_name],
        depends_on: group_deps,
      })
    }
  }

  groups
}

///|
/// トポロジカルソート（依存順）
pub fn topological_sort(groups : Array[PackageGroup]) -> Array[PackageGroup] {
  let sorted : Array[PackageGroup] = []
  let visited : Array[String] = []
  let temp_mark : Array[String] = []

  fn visit(
    name : String,
    groups : Array[PackageGroup],
    sorted : Array[PackageGroup],
    visited : Array[String],
    temp_mark : Array[String]
  ) -> Unit {
    // 一時マーク確認（循環検出）
    for t in temp_mark {
      if t == name {
        return  // 循環があれば無視
      }
    }

    // 訪問済み確認
    for v in visited {
      if v == name {
        return
      }
    }

    temp_mark.push(name)

    // このグループを見つける
    for group in groups {
      if group.name == name {
        // 依存先を先に処理
        for dep in group.depends_on {
          visit(dep, groups, sorted, visited, temp_mark)
        }

        visited.push(name)
        sorted.push(group)
        break
      }
    }

    // temp_markから削除
    let new_temp : Array[String] = []
    for t in temp_mark {
      if t != name {
        new_temp.push(t)
      }
    }
    temp_mark.clear()
    for t in new_temp {
      temp_mark.push(t)
    }
  }

  for group in groups {
    visit(group.name, groups, sorted, visited, temp_mark)
  }

  sorted
}

///|
/// グループ間の双方向依存を検出してマージ（繰り返し適用）
pub fn merge_bidirectional_groups(groups : Array[PackageGroup]) -> Array[PackageGroup] {
  let mut current = groups
  let mut changed = true

  while changed {
    changed = false
    let bi_pairs = find_bidirectional_group_pairs(current)

    if bi_pairs.length() > 0 {
      // 最初のペアをマージ
      let pair = bi_pairs[0]
      current = merge_two_groups(current, pair.0, pair.1)
      changed = true
    }
  }

  current
}

///|
fn find_bidirectional_group_pairs(groups : Array[PackageGroup]) -> Array[(String, String)] {
  let pairs : Array[(String, String)] = []

  for group_a in groups {
    for dep_name in group_a.depends_on {
      // dep_name が group_a に依存しているかチェック
      for group_b in groups {
        if group_b.name == dep_name {
          for back_dep in group_b.depends_on {
            if back_dep == group_a.name {
              // 双方向依存を発見
              // 重複を避けるため、名前順で小さい方を先に
              if group_a.name < dep_name {
                let mut found = false
                for p in pairs {
                  if p.0 == group_a.name && p.1 == dep_name {
                    found = true
                    break
                  }
                }
                if not(found) {
                  pairs.push((group_a.name, dep_name))
                }
              }
            }
          }
          break
        }
      }
    }
  }

  pairs
}

///|
fn merge_two_groups(groups : Array[PackageGroup], name_a : String, name_b : String) -> Array[PackageGroup] {
  let result : Array[PackageGroup] = []
  let mut merged_group : PackageGroup? = None
  let mut group_a : PackageGroup? = None
  let mut group_b : PackageGroup? = None

  // 対象のグループを見つける
  for g in groups {
    if g.name == name_a {
      group_a = Some(g)
    } else if g.name == name_b {
      group_b = Some(g)
    }
  }

  match (group_a, group_b) {
    (Some(a), Some(b)) => {
      // 新しいマージグループを作成
      let merged_specs : Array[String] = []
      for s in a.specs {
        merged_specs.push(s)
      }
      for s in b.specs {
        add_unique(merged_specs, s)
      }

      let merged_deps : Array[String] = []
      for d in a.depends_on {
        if d != name_b {
          add_unique(merged_deps, d)
        }
      }
      for d in b.depends_on {
        if d != name_a {
          add_unique(merged_deps, d)
        }
      }

      // マージ後の名前を決定
      let new_name = determine_group_name(merged_specs)

      merged_group = Some(PackageGroup::{
        name: new_name,
        specs: merged_specs,
        depends_on: merged_deps,
      })
    }
    _ => ()
  }

  // 結果を構築
  match merged_group {
    Some(mg) => {
      result.push(mg)

      // 他のグループを追加し、依存先を更新
      for g in groups {
        if g.name != name_a && g.name != name_b {
          // 依存先を更新
          let new_deps : Array[String] = []
          for d in g.depends_on {
            if d == name_a || d == name_b {
              add_unique(new_deps, mg.name)
            } else {
              add_unique(new_deps, d)
            }
          }
          result.push(PackageGroup::{
            name: g.name,
            specs: g.specs,
            depends_on: new_deps,
          })
        }
      }
    }
    None => {
      // マージ失敗時は元のグループをそのまま返す
      for g in groups {
        result.push(g)
      }
    }
  }

  result
}
