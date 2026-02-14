# Throws 検出カバレッジ

MDN content の `### Exceptions` セクションからの自動 throws 検出。

## データソース

[mdn/content](https://github.com/mdn/content) リポジトリの raw markdown を直接フェッチ。
各メソッド/コンストラクタ/属性セッターのページから `### Exceptions` セクションを解析。

## 検出パターン

MDN markdown から抽出される例外パターン:

1. **DOMException 名**: `` `ExceptionName` {{domxref("DOMException")}} ``
2. **JS エラー型**: `{{jsxref("TypeError")}}`, `{{jsxref("RangeError")}}` 等
3. **エラー名直接記述**: `` `SyntaxError` `` 等

## Mixin 解決

MDN は mixin 名（例: `ParentNode`）ではなく target interface 名（例: `Element`）でページを持つ。
WebIDL の `includes` 文から mixin → target の対応を構築し、MDN URL を正しい interface 名で生成。
ThrowsMap には mixin 名でエントリを格納（inject_throws の期待するキー）。

## Static メソッド

MDN は static メソッドのページ名に `_static` サフィックスを付ける（例: `response/redirect_static/index.md`）。
WebIDL の `op.special == "static"` で判別し、URL 構築時に `_static` を付加。

## Promise メソッドの throws

Promise を返すメソッドが throws を持つ場合、`Promise[Result[T, E]]` を生成。
JS 式は `.then(v => Ok).catch(e => Err(classify(e)))` パターン。

## 除外されるメンバー

以下は MDN フェッチ対象から除外され、throws 情報を持たない:

- **readonly 属性**: setter がないため throws 対象外
- **名前なし operation**: getter/setter/deleter 等の anonymous operation

## 404 レポート

MDN にページが存在しないメンバーはビルド時に集計され、以下の形式で表示:

```
Detected N throwing members from MDN (X/Y pages not found)
```

404 の主なケース:

- **新しい/実験的 API**: MDN にまだドキュメントされていない
- **WebGL 拡張**: 個別メソッドのページが存在しないことが多い
- **非標準 API**: ベンダー固有の拡張等
