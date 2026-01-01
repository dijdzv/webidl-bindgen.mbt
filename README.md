# webidl-bindgen.mbt

[![npm version](https://img.shields.io/npm/v/webidl-bindgen.mbt.svg)](https://www.npmjs.com/package/webidl-bindgen.mbt)

WebIDL to MoonBit binding generator.

## Features

- Parse WebIDL files and generate MoonBit FFI bindings
- Fetch WebIDL directly from W3C specs via `@webref/idl`
- Generate type-safe bindings for interfaces, dictionaries, enums, and typedefs
- Support for all 300+ W3C/WHATWG specifications

## Installation

```bash
npm install -g webidl-bindgen.mbt
# or
bun add -g webidl-bindgen.mbt
```

## Usage

### Generate bindings for all W3C specs

```bash
webidl-bindgen.mbt --all --per-spec -o ./src/
```

### Single spec

```bash
webidl-bindgen.mbt --spec html -o ./src/
```

### Multiple specs

```bash
webidl-bindgen.mbt --specs html,dom,cssom,fetch -o ./src/
```

### From local WebIDL file

```bash
webidl-bindgen.mbt --input canvas2d.webidl -o ./src/
```

## Options

```
-i, --input <file>      Input WebIDL file
-s, --spec <name>       Single spec from @webref/idl (e.g., html)
    --specs <list>      Comma-separated list of specs
-a, --all               Load all specs from @webref/idl
    --per-spec          Output each spec to separate file (with --all or --specs)
-o, --output <dir>      Output directory (default: ./)
-h, --help              Show this help message
```

Note: `--input`, `--spec`, `--specs`, and `--all` are mutually exclusive.

## Generated Code

The generator produces MoonBit code with:

- `pub type` declarations for interfaces and callback interfaces
- `pub extern "js" fn` for methods and attributes
- `pub enum` for WebIDL enums with `to_string`/`from_string` helpers
- `pub struct` for dictionaries with `default()` and `to_js()` methods
- `pub type` aliases for typedefs

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

## Known Limitations

Currently not supported (planned):

- Constructor generation (`new Blob()` etc.)
- Inheritance (parent interface methods)
- Static methods (`URL.createObjectURL()`)
- Special getter/setter/deleter (indexed access)

## License

MIT
