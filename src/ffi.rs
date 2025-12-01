//! Low-level FFI bindings to musubi C library
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
#![allow(dead_code)]

use std::ffi::{c_char, c_int, c_uint, c_void};
use std::os::raw::c_float;

// Constants
pub const MU_OK: c_int = 0;
pub const MU_ERRPARAM: c_int = -1;
pub const MU_ERRSRC: c_int = -2;
pub const MU_ERRFILE: c_int = -3;

pub const MU_CHUNK_MAX_SIZE: usize = 63;
pub const MU_COLOR_CODE_SIZE: usize = 32;

// Enums
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum mu_Level {
    MU_ERROR = 0,
    MU_WARNING = 1,
    MU_CUSTOM_LEVEL = 2,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum mu_IndexType {
    MU_INDEX_BYTE = 0,
    MU_INDEX_CHAR = 1,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum mu_LabelAttach {
    MU_ATTACH_MIDDLE = 0,
    MU_ATTACH_START = 1,
    MU_ATTACH_END = 2,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum mu_ColorKind {
    MU_COLOR_RESET = 0,
    MU_COLOR_ERROR = 1,
    MU_COLOR_WARNING = 2,
    MU_COLOR_KIND = 3,
    MU_COLOR_MARGIN = 4,
    MU_COLOR_SKIPPED_MARGIN = 5,
    MU_COLOR_UNIMPORTANT = 6,
    MU_COLOR_NOTE = 7,
    MU_COLOR_LABEL = 8,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum mu_Draw {
    MU_DRAW_SPACE = 0,
    MU_DRAW_NEWLINE = 1,
    MU_DRAW_LBOX = 2,
    MU_DRAW_RBOX = 3,
    MU_DRAW_COLON = 4,
    MU_DRAW_HBAR = 5,
    MU_DRAW_VBAR = 6,
    MU_DRAW_XBAR = 7,
    MU_DRAW_VBAR_BREAK = 8,
    MU_DRAW_VBAR_GAP = 9,
    MU_DRAW_UARROW = 10,
    MU_DRAW_RARROW = 11,
    MU_DRAW_LTOP = 12,
    MU_DRAW_MTOP = 13,
    MU_DRAW_RTOP = 14,
    MU_DRAW_LBOT = 15,
    MU_DRAW_MBOT = 16,
    MU_DRAW_RBOT = 17,
    MU_DRAW_LCROSS = 18,
    MU_DRAW_RCROSS = 19,
    MU_DRAW_UNDERBAR = 20,
    MU_DRAW_UNDERLINE = 21,
    MU_DRAW_ELLIPSIS = 22,
    MU_DRAW_COUNT = 23,
}

// Opaque types
#[repr(C)]
pub struct mu_Report {
    _unused: [u8; 0],
}

// mu_Line (opaque, only used as pointer)
#[repr(C)]
pub struct mu_Line {
    offset: usize,
    byte_offset: usize,
    len: c_uint,
    byte_len: c_uint,
    newline: c_uint,
}

// Function pointer types for mu_Source
pub type mu_SourceInit = unsafe extern "C" fn(src: *mut mu_Source) -> c_int;
pub type mu_SourceFree = unsafe extern "C" fn(src: *mut mu_Source);
pub type mu_SourceGetLine = unsafe extern "C" fn(src: *mut mu_Source, line_no: c_uint) -> mu_Slice;
pub type mu_SourceGetLineInfo =
    unsafe extern "C" fn(src: *mut mu_Source, line_no: c_uint) -> *const mu_Line;
pub type mu_SourceLineForChars =
    unsafe extern "C" fn(src: *mut mu_Source, char_pos: usize, out: *mut *const mu_Line) -> c_uint;
pub type mu_SourceLineForBytes =
    unsafe extern "C" fn(src: *mut mu_Source, byte_pos: usize, out: *mut *const mu_Line) -> c_uint;

/// mu_Source struct - not opaque, we need to read the `id` field
#[repr(C)]
pub struct mu_Source {
    pub ud: *mut c_void,
    pub name: mu_Slice,
    pub line_no_offset: c_int,
    pub id: mu_Id,
    pub gidx: c_int,

    pub init: Option<mu_SourceInit>,
    pub free: Option<mu_SourceFree>,
    pub get_line: Option<mu_SourceGetLine>,
    pub get_line_info: Option<mu_SourceGetLineInfo>,
    pub line_for_chars: Option<mu_SourceLineForChars>,
    pub line_for_bytes: Option<mu_SourceLineForBytes>,
}

// Type aliases
pub type mu_Id = c_uint;
pub type mu_Chunk = *const c_char;
pub type mu_Charset = [mu_Chunk; mu_Draw::MU_DRAW_COUNT as usize];

// Slice struct - matches C: struct mu_Slice { const char *p, *e; }
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct mu_Slice {
    pub p: *const c_char,
    pub e: *const c_char,
}

impl Default for mu_Slice {
    fn default() -> Self {
        Self {
            p: std::ptr::null(),
            e: std::ptr::null(),
        }
    }
}

impl From<&str> for mu_Slice {
    fn from(s: &str) -> Self {
        Self {
            p: s.as_ptr() as *const c_char,
            e: unsafe { s.as_ptr().add(s.len()) as *const c_char },
        }
    }
}

// Config struct
#[repr(C)]
#[derive(Debug)]
pub struct mu_Config {
    pub cross_gap: c_int,
    pub compact: c_int,
    pub underlines: c_int,
    pub multiline_arrows: c_int,
    pub tab_width: c_int,
    pub limit_width: c_int,
    pub ambiwidth: c_int,
    pub label_attach: mu_LabelAttach,
    pub index_type: mu_IndexType,
    pub color: Option<unsafe extern "C" fn(*mut c_void, mu_ColorKind) -> mu_Chunk>,
    pub color_ud: *mut c_void,
    pub char_set: *const mu_Charset,
}

// Color generator
#[repr(C)]
pub struct mu_ColorGen {
    pub state: [u16; 3],
    pub min_brightness: c_float,
}

pub type mu_ColorCode = [c_char; MU_COLOR_CODE_SIZE];

// Function pointer types
pub type mu_Allocf = unsafe extern "C" fn(
    ud: *mut c_void,
    p: *mut c_void,
    nsize: usize,
    osize: usize,
) -> *mut c_void;
pub type mu_Color = unsafe extern "C" fn(ud: *mut c_void, kind: mu_ColorKind) -> mu_Chunk;
pub type mu_Writer =
    unsafe extern "C" fn(ud: *mut c_void, data: *const c_char, len: usize) -> c_int;

unsafe extern "C" {
    // Report construction and configuration
    pub fn mu_new(allocf: Option<mu_Allocf>, ud: *mut c_void) -> *mut mu_Report;
    pub fn mu_reset(R: *mut mu_Report);
    pub fn mu_delete(R: *mut mu_Report);

    pub fn mu_config(R: *mut mu_Report, config: *const mu_Config) -> c_int;
    pub fn mu_label(R: *mut mu_Report, start: usize, end: usize, src_id: mu_Id) -> c_int;
    pub fn mu_message(R: *mut mu_Report, msg: mu_Slice, width: c_int) -> c_int;
    pub fn mu_color(
        R: *mut mu_Report,
        color: Option<unsafe extern "C" fn(*mut c_void, mu_ColorKind) -> mu_Chunk>,
        ud: *mut c_void,
    ) -> c_int;
    pub fn mu_order(R: *mut mu_Report, order: c_int) -> c_int;
    pub fn mu_priority(R: *mut mu_Report, priority: c_int) -> c_int;

    pub fn mu_title(R: *mut mu_Report, l: mu_Level, custom: mu_Slice, msg: mu_Slice) -> c_int;
    pub fn mu_code(R: *mut mu_Report, code: mu_Slice) -> c_int;
    pub fn mu_help(R: *mut mu_Report, help_msg: mu_Slice) -> c_int;
    pub fn mu_note(R: *mut mu_Report, note_msg: mu_Slice) -> c_int;

    // Rendering
    pub fn mu_source(R: *mut mu_Report, src: *mut mu_Source) -> c_int;
    pub fn mu_writer(R: *mut mu_Report, writer: Option<mu_Writer>, ud: *mut c_void) -> c_int;
    pub fn mu_render(R: *mut mu_Report, pos: usize, src_id: mu_Id) -> c_int;

    // Charsets
    pub fn mu_ascii() -> *const mu_Charset;
    pub fn mu_unicode() -> *const mu_Charset;

    // Default color
    pub fn mu_default_color(ud: *mut c_void, kind: mu_ColorKind) -> mu_Chunk;

    // Config initialization
    pub fn mu_initconfig(config: *mut mu_Config);

    // Source creation
    pub fn mu_newsource(R: *mut mu_Report, size: usize, name: mu_Slice) -> *mut mu_Source;
    pub fn mu_memory_source(R: *mut mu_Report, data: mu_Slice, name: mu_Slice) -> *mut mu_Source;

    // Color generator
    pub fn mu_initcolorgen(cg: *mut mu_ColorGen, min_brightness: c_float);
    pub fn mu_gencolor(cg: *mut mu_ColorGen, out: *mut mu_ColorCode);
    pub fn mu_fromcolorcode(ud: *mut c_void, kind: mu_ColorKind) -> mu_Chunk;
}
