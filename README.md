# webidl-bindgen.mbt

[![npm version](https://img.shields.io/npm/v/webidl-bindgen.mbt.svg)](https://www.npmjs.com/package/webidl-bindgen.mbt)

WebIDL to MoonBit binding generator. Loads all 300+ W3C/WHATWG specifications via `@webref/idl` and generates type-safe MoonBit FFI bindings for JavaScript interop.

Built primarily for [websys.mbt](https://github.com/dijdzv/websys.mbt).

## Features

- Load all W3C/WHATWG specs via `@webref/idl` and generate per-spec `.mbt` files
- Type-safe bindings for interfaces, dictionaries, enums, typedefs, and union types
- Automatic throws detection from MDN content (methods returning `Result[T, JsError]`)
- Inheritance resolution, mixin merging, and cross-spec type ownership
- Constructor, static method, getter/setter/deleter, maplike/setlike, iterable support

## Installation

```bash
npm install -g webidl-bindgen.mbt
# or
bun add -g webidl-bindgen.mbt
```

## Usage

```bash
webidl-bindgen.mbt -o ./src/
```

### Options

```
-o, --output <dir>  Output directory (default: ./)
-h, --help          Show this help message
```

## Generated Code

The generator produces MoonBit code with:

- `pub type` declarations for interfaces and callback interfaces
- `pub extern "js" fn` for methods and attributes
- `pub enum` for WebIDL enums with `to_string`/`from_string` helpers
- `pub struct` for dictionaries with `default()` and `to_js()` methods
- `pub type` aliases for typedefs
- Union types with `from_*` factory functions and `as_*` / `bind_as_*` helpers
- `Result[T, JsError]` for methods that throw (detected from MDN)

## Example Output

```moonbit
/// HTMLElement interface
pub type HTMLElement

/// Get the inner text
pub extern "js" fn HTMLElement::inner_text(self : HTMLElement) -> String =
  #| (self) => self.innerText

/// Set the inner text
pub extern "js" fn HTMLElement::set_inner_text(self : HTMLElement, value : String) -> Unit =
  #| (self, value) => { self.innerText = value }
```

## Dependencies

- [webidl2](https://github.com/AliasT/webidl2.js) - WebIDL parser
- [@webref/idl](https://github.com/nicolo-ribaudo/webref) - W3C spec IDL collection

## License

MIT
