package = "musubi"
version = "0.3.0-3"
source = {
   url = "https://github.com/starwing/musubi/archive/refs/tags/v0.3.0.tar.gz",
   dir = "musubi-0.3.0"
}
description = {
   summary = "A beautiful diagnostics renderer for compiler errors and warnings",
   detailed = [[
Musubi (結び, "connection" in Japanese) is a high-performance diagnostics renderer 
inspired by Rust's Ariadne library. It produces beautiful, color-coded diagnostic 
messages with precise source location highlighting, multi-line spans, and intelligent 
label clustering.

Features:
- Multi-line diagnostics with color-coded labels
- Intelligent label clustering and virtual row rendering
- Unicode and CJK character support (full-width characters, emoji, regional indicators)
- ASCII/Unicode glyph sets for terminal compatibility
- Line width limiting with smart truncation
- Customizable colors, character sets, and layout options
- Zero-copy source file handling with streaming support

This package provides C library with Lua bindings. A pure Lua implementation is also 
available (ariadne.lua). For Rust users, see the musubi-rs crate on crates.io.
]],
   homepage = "https://github.com/starwing/musubi",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
      musubi = "musubi.c"
   }
}
