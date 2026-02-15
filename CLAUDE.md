# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WebIDL to MoonBit binding generator. Parses WebIDL files and generates type-safe MoonBit FFI bindings for JavaScript interop. Supports fetching WebIDL directly from W3C/WHATWG specs via `@webref/idl`.

## Build and Development Commands

```bash
# Build the project (compiles MoonBit to JS and adds shebang)
bun run build

# Run locally during development (after build)
bun _build/js/release/build/webidl-bindgen.js --help

# Run tests
moon test

# Format code
moon fmt

# Type check
moon check
```

## Architecture

The codebase is a single MoonBit package (`src/`) that compiles to a CLI tool targeting JavaScript (Bun).

### Core Files

- **main.mbt** - CLI entry point. Handles argument parsing, file I/O, and orchestrates the generation pipeline
- **parser.mbt** - WebIDL parser FFI. Wraps `webidl2.js` to parse WebIDL text into JavaScript AST
- **ast.mbt** - MoonBit AST type definitions (`Definition`, `InterfaceDef`, `DictionaryDef`, `IdlType`, etc.)
- **webref.mbt** - `@webref/idl` FFI for fetching WebIDL from W3C specs

### Code Generation

- **gen_interface.mbt** - Generates interface bindings: methods, attributes, constructors, special operations (getter/setter/deleter), maplike/setlike, constants. Handles method overloading and optional arguments
- **gen_types.mbt** - Generates enum, dictionary, and typedef bindings. Handles Union types with factory functions and type checks
- **formatter.mbt** - Output formatting, definition merging, inheritance resolution, and cross-spec type ownership

### Key Patterns

**WebIDL to MoonBit Type Mapping** (in `gen_interface.mbt:idl_type_to_moonbit`):
- `boolean` → `Bool`, integer types → `Int`/`Int64`, floating types → `Double`
- `DOMString` → `String`, `sequence<T>` → `Array[T]`, `Promise<T>` → `Promise[T]`
- Union types become opaque types with `from_*` factory functions

**Enum Handling**: WebIDL enums become MoonBit enums with `to_string`/`from_string` helpers. When passed to JS APIs, they're converted via array index lookup.

**Per-Spec Output**: Generates separate `.mbt` files per spec with a `shared.mbt` for common types. Uses type ownership tracking to avoid duplicate definitions.

**Throws Detection**: Fetches MDN content pages and parses `### Exceptions` sections to detect throwing methods. These are generated as `Result[T, JsError]` return types.

## Release (moon-release)

[moon-release](https://github.com/dijdzv/moon-release) によるリリース自動化を使用。

### Conventional Commits

コミットメッセージは **Conventional Commits** 形式に従うこと:

| Type | Version Bump | Example |
|---|---|---|
| `feat:` | Minor (0.x.0) | `feat: add new feature` |
| `fix:` | Patch (0.0.x) | `fix: resolve bug` |
| `feat!:` / `fix!:` | Major (x.0.0) | `feat!: breaking change` |

- `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore` はバージョンバンプ**しない**
- コミットの影響範囲に応じて適切な type を選択すること

### リリースフロー

1. main ブランチへの push で release PR が自動作成・更新される
2. release PR を **squash merge** すると、タグ作成・GitHub Release・npm publish が実行される
3. release PR のタイトルは `chore: release v{{ version }}` 形式（自動生成）

## CLI Usage

```bash
webidl-bindgen.mbt -o ./src/
```
