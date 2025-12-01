//! Safe Rust wrapper for musubi diagnostic renderer
//!
//! # Example
//!
//! ```rust
//! use musubi::{Report, Level};
//!
//! let mut report = Report::new()
//!     .with_source(("let x = 42;", "example.rs"))
//!     .with_title(Level::Error, "Invalid syntax")
//!     .with_code("E001")
//!     .with_label(0..3)
//!     .with_message("expected identifier");
//!
//! println!("{}", report.render_to_string(0, 0));
//! ```

mod ffi;

use std::ffi::{c_char, c_int, c_void};
use std::fmt::Debug;
use std::io::{self, Write};
use std::marker::PhantomData;
use std::mem::MaybeUninit;
use std::ptr::{self, null_mut};

// ============================================================================
// Public types (no FFI exposure)
// ============================================================================

/// Diagnostic severity level
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    /// Error level diagnostic
    Error,
    /// Warning level diagnostic
    Warning,
}

impl From<Level> for ffi::mu_Level {
    fn from(level: Level) -> Self {
        match level {
            Level::Error => ffi::mu_Level::MU_ERROR,
            Level::Warning => ffi::mu_Level::MU_WARNING,
        }
    }
}

/// Where labels attach to their spans
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LabelAttach {
    /// Attach in the middle of the span
    #[default]
    Middle,
    /// Attach at the start of the span
    Start,
    /// Attach at the end of the span
    End,
}

impl From<LabelAttach> for ffi::mu_LabelAttach {
    fn from(attach: LabelAttach) -> Self {
        match attach {
            LabelAttach::Middle => ffi::mu_LabelAttach::MU_ATTACH_MIDDLE,
            LabelAttach::Start => ffi::mu_LabelAttach::MU_ATTACH_START,
            LabelAttach::End => ffi::mu_LabelAttach::MU_ATTACH_END,
        }
    }
}

/// Index type for span positions
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum IndexType {
    /// Index by byte offset
    Byte,
    /// Index by character offset
    #[default]
    Char,
}

impl From<IndexType> for ffi::mu_IndexType {
    fn from(index_type: IndexType) -> Self {
        match index_type {
            IndexType::Byte => ffi::mu_IndexType::MU_INDEX_BYTE,
            IndexType::Char => ffi::mu_IndexType::MU_INDEX_CHAR,
        }
    }
}

/// Color categories for diagnostic output
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ColorKind {
    Reset,
    Error,
    Warning,
    Kind,
    Margin,
    SkippedMargin,
    Unimportant,
    Note,
    Label,
}

impl From<ColorKind> for ffi::mu_ColorKind {
    fn from(kind: ColorKind) -> Self {
        match kind {
            ColorKind::Reset => ffi::mu_ColorKind::MU_COLOR_RESET,
            ColorKind::Error => ffi::mu_ColorKind::MU_COLOR_ERROR,
            ColorKind::Warning => ffi::mu_ColorKind::MU_COLOR_WARNING,
            ColorKind::Kind => ffi::mu_ColorKind::MU_COLOR_KIND,
            ColorKind::Margin => ffi::mu_ColorKind::MU_COLOR_MARGIN,
            ColorKind::SkippedMargin => ffi::mu_ColorKind::MU_COLOR_SKIPPED_MARGIN,
            ColorKind::Unimportant => ffi::mu_ColorKind::MU_COLOR_UNIMPORTANT,
            ColorKind::Note => ffi::mu_ColorKind::MU_COLOR_NOTE,
            ColorKind::Label => ffi::mu_ColorKind::MU_COLOR_LABEL,
        }
    }
}

impl ColorKind {
    fn from_ffi(kind: ffi::mu_ColorKind) -> Self {
        match kind {
            ffi::mu_ColorKind::MU_COLOR_RESET => ColorKind::Reset,
            ffi::mu_ColorKind::MU_COLOR_ERROR => ColorKind::Error,
            ffi::mu_ColorKind::MU_COLOR_WARNING => ColorKind::Warning,
            ffi::mu_ColorKind::MU_COLOR_KIND => ColorKind::Kind,
            ffi::mu_ColorKind::MU_COLOR_MARGIN => ColorKind::Margin,
            ffi::mu_ColorKind::MU_COLOR_SKIPPED_MARGIN => ColorKind::SkippedMargin,
            ffi::mu_ColorKind::MU_COLOR_UNIMPORTANT => ColorKind::Unimportant,
            ffi::mu_ColorKind::MU_COLOR_NOTE => ColorKind::Note,
            ffi::mu_ColorKind::MU_COLOR_LABEL => ColorKind::Label,
        }
    }
}

// ============================================================================
// Title level types
// ============================================================================

/// Internal representation of a title level for FFI.
///
/// This enables flexible title creation:
/// - `.with_title(Level::Error, "message")` - standard level
/// - `.with_title("Note", "message")` - custom level name
pub struct TitleLevel<'a> {
    level: ffi::mu_Level,
    custom_name: ffi::mu_Slice,
    _marker: PhantomData<&'a ()>,
}

/// Standard level
impl From<Level> for TitleLevel<'_> {
    fn from(level: Level) -> Self {
        TitleLevel {
            level: level.into(),
            custom_name: Default::default(),
            _marker: PhantomData,
        }
    }
}

/// Custom level: string name
impl<'a> From<&'a str> for TitleLevel<'a> {
    fn from(name: &'a str) -> Self {
        TitleLevel {
            level: ffi::mu_Level::MU_CUSTOM_LEVEL,
            custom_name: name.into(),
            _marker: PhantomData,
        }
    }
}

/// Character set for rendering
#[derive(Default, Debug, Clone, Copy, PartialEq, Eq)]
pub struct CharSet {
    pub space: char,
    pub newline: char,
    pub lbox: char,
    pub rbox: char,
    pub colon: char,
    pub hbar: char,
    pub vbar: char,
    pub xbar: char,
    pub vbar_break: char,
    pub vbar_gap: char,
    pub uarrow: char,
    pub rarrow: char,
    pub ltop: char,
    pub mtop: char,
    pub rtop: char,
    pub lbot: char,
    pub mbot: char,
    pub rbot: char,
    pub lcross: char,
    pub rcross: char,
    pub underbar: char,
    pub underline: char,
    pub ellipsis: char,
}

impl From<*const ffi::mu_Charset> for CharSet {
    fn from(ptr: *const ffi::mu_Charset) -> Self {
        fn slice_to_char(s: *const c_char) -> char {
            if s.is_null() {
                return ' ';
            }
            unsafe {
                let len = *s as usize;
                let bytes = std::slice::from_raw_parts(s.add(1) as *const u8, len);
                std::str::from_utf8(bytes)
                    .unwrap_or(" ")
                    .chars()
                    .next()
                    .unwrap_or(' ')
            }
        }
        unsafe {
            let chars = &*ptr;
            CharSet {
                space: slice_to_char(chars[0]),
                newline: slice_to_char(chars[1]),
                lbox: slice_to_char(chars[2]),
                rbox: slice_to_char(chars[3]),
                colon: slice_to_char(chars[4]),
                hbar: slice_to_char(chars[5]),
                vbar: slice_to_char(chars[6]),
                xbar: slice_to_char(chars[7]),
                vbar_break: slice_to_char(chars[8]),
                vbar_gap: slice_to_char(chars[9]),
                uarrow: slice_to_char(chars[10]),
                rarrow: slice_to_char(chars[11]),
                ltop: slice_to_char(chars[12]),
                mtop: slice_to_char(chars[13]),
                rtop: slice_to_char(chars[14]),
                lbot: slice_to_char(chars[15]),
                mbot: slice_to_char(chars[16]),
                rbot: slice_to_char(chars[17]),
                lcross: slice_to_char(chars[18]),
                rcross: slice_to_char(chars[19]),
                underbar: slice_to_char(chars[20]),
                underline: slice_to_char(chars[21]),
                ellipsis: slice_to_char(chars[22]),
            }
        }
    }
}

impl CharSet {
    /// Predefined ASCII character set
    pub fn ascii() -> CharSet {
        unsafe { ffi::mu_ascii() }.into()
    }

    /// Predefined Unicode character set
    pub fn unicode() -> CharSet {
        unsafe { ffi::mu_unicode() }.into()
    }
}

// ============================================================================
// Color types
// ============================================================================

/// Trait for types that can provide color codes.
///
/// Similar to `Display`, this trait allows custom color implementations
/// without heap allocation.
///
/// # Example
/// ```ignore
/// struct MyColors;
///
/// impl Color for MyColors {
///     fn color(&self, kind: ColorKind, out: &mut ColorCode) {
///         match kind {
///             ColorKind::Error => out.write_str("\x1b[31m"),
///             ColorKind::Reset => out.write_str("\x1b[0m"),
///             _ => {}
///         }
///     }
/// }
/// ```
pub trait Color {
    fn color(&self, w: &mut dyn Write, kind: ColorKind) -> std::io::Result<()>;
}

struct ColorUd {
    color_obj: *const c_void,
    color_buf: *mut [u8; ffi::MU_COLOR_CODE_SIZE],
}

/// Configuration for the diagnostic renderer
pub struct Config<'a> {
    inner: ffi::mu_Config,
    color_ud: Option<Box<ColorUd>>,
    char_set: Option<&'a CharSet>,
}

impl Debug for Config<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Config")
            .field("cross_gap", &self.inner.cross_gap)
            .field("compact", &self.inner.compact)
            .field("underlines", &self.inner.underlines)
            .field("multiline_arrows", &self.inner.multiline_arrows)
            .field("tab_width", &self.inner.tab_width)
            .field("limit_width", &self.inner.limit_width)
            .field("ambiwidth", &self.inner.ambiwidth)
            .field("label_attach", &self.inner.label_attach)
            .field("index_type", &self.inner.index_type)
            .finish()
    }
}

impl<'a> Clone for Config<'_> {
    fn clone(&self) -> Self {
        let new: ffi::mu_Config = unsafe { std::mem::transmute_copy(&self.inner) };
        Self {
            inner: new,
            color_ud: None,
            char_set: self.char_set,
        }
    }
}

impl Default for Config<'_> {
    fn default() -> Self {
        let mut obj = MaybeUninit::uninit();
        unsafe {
            ffi::mu_initconfig(obj.as_mut_ptr());
        }
        Self {
            inner: unsafe { obj.assume_init() },
            color_ud: None,
            char_set: None,
        }
    }
}

impl<'a> Config<'a> {
    /// Create a new config with default values.
    pub fn new() -> Self {
        Self::default()
    }

    /// Enable or disable cross gap rendering.
    pub fn with_cross_gap(mut self, enabled: bool) -> Self {
        self.inner.cross_gap = enabled as c_int;
        self
    }

    /// Enable or disable compact mode.
    pub fn with_compact(mut self, enabled: bool) -> Self {
        self.inner.compact = enabled as c_int;
        self
    }

    /// Enable or disable underlines.
    pub fn with_underlines(mut self, enabled: bool) -> Self {
        self.inner.underlines = enabled as c_int;
        self
    }

    /// Enable or disable multiline arrows.
    pub fn with_multiline_arrows(mut self, enabled: bool) -> Self {
        self.inner.multiline_arrows = enabled as c_int;
        self
    }

    /// Set the tab width for rendering.
    pub fn with_tab_width(mut self, width: i32) -> Self {
        self.inner.tab_width = width;
        self
    }

    /// Set the width limit for line wrapping (0 = no limit).
    pub fn with_limit_width(mut self, width: i32) -> Self {
        self.inner.limit_width = width;
        self
    }

    /// Set the ambiguous character width (1 or 2).
    pub fn with_ambiwidth(mut self, width: i32) -> Self {
        self.inner.ambiwidth = width;
        self
    }

    /// Set where labels attach to spans.
    pub fn with_label_attach(mut self, attach: LabelAttach) -> Self {
        self.inner.label_attach = attach.into();
        self
    }

    /// Set the index type (char or byte).
    pub fn with_index_type(mut self, index_type: IndexType) -> Self {
        self.inner.index_type = index_type.into();
        self
    }

    /// Set ASCII character set.
    pub fn with_char_set_ascii(mut self) -> Self {
        self.inner.char_set = unsafe { ffi::mu_ascii() };
        self.char_set = None;
        self
    }

    /// Set Unicode character set.
    pub fn with_char_set_unicode(mut self) -> Self {
        self.inner.char_set = unsafe { ffi::mu_unicode() };
        self.char_set = None;
        self
    }

    /// Set the character set (ASCII or Unicode).
    pub fn with_char_set(mut self, char_set: &'a CharSet) -> Self {
        self.char_set = Some(char_set);
        self
    }

    /// Enable default ANSI colors.
    pub fn with_color_default(mut self) -> Self {
        self.inner.color = Some(ffi::mu_default_color);
        self.color_ud = None;
        self
    }

    /// Disable color output.
    pub fn with_color_disabled(mut self) -> Self {
        self.inner.color = None;
        self.color_ud = None;
        self
    }

    /// Set a custom color provider.
    pub fn with_color<C>(mut self, color: &'a C) -> Self
    where
        C: Color,
    {
        extern "C" fn color_fn<C: Color>(
            ud: *mut c_void,
            kind: ffi::mu_ColorKind,
        ) -> ffi::mu_Chunk {
            let ud = unsafe { &mut *(ud as *mut ColorUd) };
            let color = unsafe { &*(ud.color_obj as *const C) };
            let buf = unsafe { &mut *ud.color_buf };
            let mut remain = &mut buf[1..];
            match color.color(&mut remain, ColorKind::from_ffi(kind)) {
                Ok(_) => {
                    let used = (ffi::MU_COLOR_CODE_SIZE - remain.len() - 1) as u8;
                    buf[0] = used;
                    buf.as_ptr() as *const c_char
                }
                Err(_) => b"\0" as *const u8 as *const c_char,
            }
        }

        self.color_ud = Some(Box::new(ColorUd {
            color_obj: color as *const C as *mut c_void,
            color_buf: null_mut(),
        }));
        self.inner.color = Some(color_fn::<C>);
        self.inner.color_ud = self
            .color_ud
            .as_ref()
            .map_or(null_mut(), |ud| &**ud as *const ColorUd as *mut c_void);
        self
    }
}

// ============================================================================
// Source types
// ============================================================================

/// A source of diagnostic content.
///
/// Sources can be created from in-memory strings or with custom line providers.
///
/// # Example
/// ```ignore
/// // Simple in-memory source
/// let source = Source::new("let x = 42;", "main.rs");
///
/// // Or use tuple syntax with Report
/// report.with_source(("let x = 42;", "main.rs"));
/// ```
pub struct Source<'a> {
    content: &'a str,
    name: &'a str,
    line_no_offset: i32,
}

impl<'a> Source<'a> {
    /// Create a new source from content and name.
    pub fn new(content: &'a str, name: &'a str) -> Self {
        Self {
            content,
            name,
            line_no_offset: 0,
        }
    }

    /// Set the line number offset (default: 0).
    ///
    /// This adjusts the displayed line numbers. For example, if your
    /// source starts at line 10 in the original file, set offset to 9.
    pub fn with_line_offset(mut self, offset: i32) -> Self {
        self.line_no_offset = offset;
        self
    }
}

impl<'a> From<(&'a str, &'a str)> for Source<'a> {
    fn from(value: (&'a str, &'a str)) -> Self {
        Source::new(value.0, value.1)
    }
}

// ============================================================================
// Label span types
// ============================================================================

/// A label span with optional source ID.
///
/// The `src_id` is the registration order of sources (0 for first, 1 for second, etc.).
///
/// This enables flexible label creation:
/// - `.with_label_at((0..10, 0))` - tuple of (range, src_id)
#[derive(Debug, Clone, Copy)]
pub struct LabelSpan {
    pub start: usize,
    pub end: usize,
    pub src_id: ffi::mu_Id,
}

/// Range
impl From<std::ops::Range<usize>> for LabelSpan {
    fn from(value: std::ops::Range<usize>) -> Self {
        LabelSpan {
            start: value.start,
            end: value.end,
            src_id: 0,
        }
    }
}

impl From<std::ops::Range<i32>> for LabelSpan {
    fn from(value: std::ops::Range<i32>) -> Self {
        LabelSpan {
            start: value.start.max(0) as usize,
            end: value.end.max(0) as usize,
            src_id: 0,
        }
    }
}

/// (Range, usize) tuple
impl From<(std::ops::Range<usize>, usize)> for LabelSpan {
    fn from(value: (std::ops::Range<usize>, usize)) -> Self {
        LabelSpan {
            start: value.0.start,
            end: value.0.end,
            src_id: value.1 as ffi::mu_Id,
        }
    }
}

/// (Range, usize) tuple
impl From<(std::ops::Range<i32>, usize)> for LabelSpan {
    fn from(value: (std::ops::Range<i32>, usize)) -> Self {
        LabelSpan {
            start: value.0.start.max(0) as usize,
            end: value.0.end.max(0) as usize,
            src_id: value.1 as ffi::mu_Id,
        }
    }
}

// ============================================================================
// Report
// ============================================================================

/// A diagnostic report builder.
///
/// The lifetime `'a` indicates that all string references passed to the report
/// must live at least as long as the report itself. This enables zero-copy
/// string passing to the underlying C library.
///
/// # Source Registration
///
/// Sources are registered with [`with_source()`](Self::with_source) and assigned IDs
/// based on registration order: first source is 0, second is 1, etc.
///
/// # Example
/// ```rust
/// use musubi::{Report, Level};
///
/// let mut report = Report::new();
/// report
///     .with_source(("let x = 42;", "main.rs"))   // src_id = 0
///     .with_source(("fn foo() {}", "lib.rs"))    // src_id = 1
///     .with_title(Level::Error, "Error")
///     .with_label((0..3, 0usize)) // label in source 0
///     .with_message("here")
///     .with_label((3..6, 1usize)) // label in source 1
///     .with_message("and here");
/// ```
///
/// # Lifetime Safety
///
/// Source strings must outlive the report. This will not compile:
///
/// ```compile_fail
/// use musubi::{Report, Level};
///
/// fn bad() -> String {
///     let mut report = Report::new();
///     {
///         let code = String::from("let x = 42;");
///         report.with_source((code.as_str(), "test.rs"));
///     }  // code dropped here, but report still holds reference
///     report.render_to_string(0, 0)
/// }
/// ```
pub struct Report<'a> {
    ptr: *mut ffi::mu_Report,
    config: Option<Config<'a>>,
    color_uds: Vec<Box<ColorUd>>,
    _marker: PhantomData<&'a str>,
}

impl<'a> Report<'a> {
    /// Create a new report.
    pub fn new() -> Self {
        let ptr = unsafe { ffi::mu_new(None, ptr::null_mut()) };
        assert!(!ptr.is_null(), "Failed to allocate report");
        Self {
            ptr,
            config: None,
            color_uds: Vec::new(),
            _marker: PhantomData,
        }
    }

    /// Configure the report.
    pub fn with_config(mut self, config: Config<'a>) -> Self {
        self.config = Some(config);
        self
    }

    /// Reset the report for reuse.
    pub fn reset(self) -> Self {
        unsafe { ffi::mu_reset(self.ptr) };
        self
    }

    /// Register a source with the report.
    ///
    /// Sources are assigned IDs based on registration order:
    /// - First source registered gets ID 0
    /// - Second source gets ID 1
    /// - And so on...
    ///
    /// The source is consumed and managed by the report.
    ///
    /// # Example
    /// ```rust
    /// use musubi::{Report, Source};
    ///
    /// let mut report = Report::new();
    /// report
    ///     .with_source(("code", "file.rs"))           // ID 0
    ///     .with_source(Source::new("x", "other.rs")); // ID 1
    /// ```
    pub fn with_source<S: Into<Source<'a>>>(self, source: S) -> Self {
        let src = source.into();
        let src_ptr =
            unsafe { ffi::mu_memory_source(self.ptr, src.content.into(), src.name.into()) };
        // Set line offset if non-zero
        if src.line_no_offset != 0 {
            unsafe {
                (*src_ptr).line_no_offset = src.line_no_offset;
            }
        }
        let result = unsafe { ffi::mu_source(self.ptr, src_ptr) };
        assert!(result == ffi::MU_OK, "Failed to register source");
        self
    }

    /// Set the title and level.
    ///
    /// Accepts either a standard level or a custom level name:
    /// - `with_title(Level::Error, "message")` - standard level
    /// - `with_title("Note", "message")` - custom level name
    ///
    /// # Example
    /// ```rust
    /// use musubi::{Report, Level};
    ///
    /// let mut report = Report::new();
    /// report.with_title(Level::Error, "Something went wrong");
    /// // Or with custom level:
    /// // report.with_title("Note", "Something to note");
    /// ```
    pub fn with_title<L: Into<TitleLevel<'a>>>(self, level: L, message: &'a str) -> Self {
        let tl = level.into();
        unsafe { ffi::mu_title(self.ptr, tl.level, tl.custom_name, message.into()) };
        self
    }

    /// Set the error code.
    pub fn with_code(self, code: &'a str) -> Self {
        unsafe { ffi::mu_code(self.ptr, code.into()) };
        self
    }

    /// Add a label at the given byte range.
    ///
    /// The `src_id` is the source registration order (0 for first source, 1 for second, etc.).
    ///
    /// # Example
    /// ```rust
    /// use musubi::{Report, Level};
    ///
    /// let mut report = Report::new();
    /// report
    ///     .with_source(("let x = 42;", "main.rs"))
    ///     .with_title(Level::Error, "Error")
    ///     .with_label((0..3, 0usize))  // label in source 0
    ///     .with_message("here");
    /// ```
    pub fn with_label<L: Into<LabelSpan>>(self, span: L) -> Self {
        let span = span.into();
        unsafe { ffi::mu_label(self.ptr, span.start, span.end, span.src_id) };
        self
    }

    /// Set the message for the last added label.
    pub fn with_message(self, msg: &'a str) -> Self {
        let width = unicode_width(msg);
        unsafe { ffi::mu_message(self.ptr, msg.into(), width) };
        self
    }

    /// Set the color for the last added label.
    pub fn with_color<C: Color>(mut self, color: &'a C) -> Self {
        self.color_uds.push(Box::new(ColorUd {
            color_obj: color as *const _ as *const c_void,
            color_buf: Box::into_raw(Box::new([0u8; ffi::MU_COLOR_CODE_SIZE])),
        }));
        extern "C" fn color_fn<C: Color>(
            ud: *mut c_void,
            kind: ffi::mu_ColorKind,
        ) -> ffi::mu_Chunk {
            let ud = unsafe { &mut *(ud as *mut ColorUd) };
            let color = unsafe { &*(ud.color_obj as *const C) };
            let buf = unsafe { &mut *ud.color_buf };
            let mut remain = &mut buf[1..];
            match color.color(&mut remain, ColorKind::from_ffi(kind)) {
                Ok(_) => {
                    let used = (ffi::MU_COLOR_CODE_SIZE - remain.len() - 1) as u8;
                    buf[0] = used;
                    return buf.as_ptr() as *const c_char;
                }
                Err(_) => b"\0".as_ptr() as *const c_char,
            }
        }
        unsafe {
            ffi::mu_color(
                self.ptr,
                Some(color_fn::<C>),
                &**self.color_uds.last().unwrap() as *const ColorUd as *mut c_void,
            )
        };
        self
    }

    /// Set the order for the last added label.
    pub fn with_order(self, order: i32) -> Self {
        unsafe { ffi::mu_order(self.ptr, order) };
        self
    }

    /// Set the priority for the last added label.
    pub fn with_priority(self, priority: i32) -> Self {
        unsafe { ffi::mu_priority(self.ptr, priority) };
        self
    }

    /// Add a help message.
    pub fn with_help(self, msg: &'a str) -> Self {
        unsafe { ffi::mu_help(self.ptr, msg.into()) };
        self
    }

    /// Add a note message.
    pub fn with_note(self, msg: &'a str) -> Self {
        unsafe { ffi::mu_note(self.ptr, msg.into()) };
        self
    }

    /// Render the report to a String.
    ///
    /// - `pos`: The byte position in the source for header location display
    /// - `src_id`: The primary source ID (registration order)
    pub fn render_to_string(&mut self, pos: usize, src_id: usize) -> String {
        let mut writer = Vec::new();
        unsafe extern "C" fn string_writer_callback(
            ud: *mut c_void,
            data: *const c_char,
            len: usize,
        ) -> c_int {
            let writer = unsafe { &mut *(ud as *mut Vec<u8>) };
            let slice = unsafe { std::slice::from_raw_parts(data as *const u8, len) };
            writer.extend_from_slice(slice);
            ffi::MU_OK
        }
        unsafe {
            ffi::mu_writer(
                self.ptr,
                Some(string_writer_callback),
                &mut writer as *mut Vec<u8> as *mut c_void,
            )
        };
        self.render(pos, src_id);
        String::from_utf8(writer)
            .unwrap_or_else(|e| String::from_utf8_lossy(&e.into_bytes()).into_owned())
    }

    /// Render the report to stdout.
    pub fn render_to_stdout(&mut self, pos: usize, src_id: usize) {
        unsafe extern "C" fn stdout_writer_callback(
            _ud: *mut c_void,
            data: *const c_char,
            len: usize,
        ) -> c_int {
            let slice = unsafe { std::slice::from_raw_parts(data as *const u8, len) };
            let mut stdout = io::stdout();
            if stdout.write_all(slice).is_ok() && stdout.flush().is_ok() {
                ffi::MU_OK
            } else {
                ffi::MU_ERRPARAM
            }
        }

        unsafe { ffi::mu_writer(self.ptr, Some(stdout_writer_callback), ptr::null_mut()) };
        self.render(pos, src_id);
    }

    /// Render the report to a writer.
    pub fn render_to_writer<W: Write>(
        &mut self,
        pos: usize,
        src_id: usize,
        writer: &mut W,
    ) -> io::Result<()> {
        struct WriterWrapper<'a, W: Write> {
            writer: &'a mut W,
            result: io::Result<()>,
        }

        unsafe extern "C" fn writer_callback<W: Write>(
            ud: *mut c_void,
            data: *const c_char,
            len: usize,
        ) -> c_int {
            let w = unsafe { &mut *(ud as *mut WriterWrapper<W>) };
            let slice = unsafe { std::slice::from_raw_parts(data as *const u8, len) };
            match w.writer.write_all(slice) {
                Ok(_) => ffi::MU_OK,
                Err(e) => {
                    w.result = Err(e);
                    ffi::MU_ERRFILE
                }
            }
        }
        let mut wrapper = WriterWrapper {
            writer,
            result: Ok(()),
        };
        unsafe {
            ffi::mu_writer(
                self.ptr,
                Some(writer_callback::<W>),
                &mut wrapper as *mut WriterWrapper<W> as *mut c_void,
            );
        }
        match self.render(pos, src_id) {
            ffi::MU_ERRFILE => return wrapper.result,
            _ => Ok(()),
        }
    }

    fn render(&mut self, pos: usize, src_id: usize) -> c_int {
        let mut buf = [0u8; ffi::MU_COLOR_CODE_SIZE];
        let cs_buf: CharSetBuf;
        let cs: ffi::mu_Charset;
        if let Some(config) = &mut self.config {
            if let Some(char_set) = config.char_set {
                cs_buf = (*char_set).into();
                cs = cs_buf.into();
                config.inner.char_set = &cs as *const ffi::mu_Charset;
                println!("Using custom char set: {:p}", config.inner.char_set);
            }
        }
        if let Some(cfg) = self.config.as_mut() {
            cfg.color_ud.as_mut().map(|color_ud| {
                color_ud.color_buf = &mut buf as *mut [u8; ffi::MU_COLOR_CODE_SIZE];
            });
        }
        for color_ud in &mut self.color_uds {
            color_ud.color_buf = &mut buf as *mut [u8; ffi::MU_COLOR_CODE_SIZE];
        }
        if let Some(cfg) = &self.config {
            unsafe { ffi::mu_config(self.ptr, &cfg.inner) };
        }
        unsafe { ffi::mu_render(self.ptr, pos, src_id as ffi::mu_Id) }
    }
}

struct CharSetBuf {
    buf: [[u8; 8]; 23],
}

impl From<CharSetBuf> for ffi::mu_Charset {
    fn from(value: CharSetBuf) -> Self {
        let mut chars: ffi::mu_Charset = [ptr::null(); 23];
        for (i, slice) in value.buf.iter().enumerate() {
            chars[i] = slice.as_ptr() as *const c_char;
        }
        chars
    }
}

impl From<CharSet> for CharSetBuf {
    fn from(char_set: CharSet) -> Self {
        fn char_to_slice(c: char) -> [u8; 8] {
            let mut buf = [0u8; 8];
            let s = c.encode_utf8(&mut buf);
            let len = s.len() as u8;
            let mut result = [0u8; 8];
            result[0] = len;
            result[1..(len as usize + 1)].copy_from_slice(s.as_bytes());
            result
        }
        CharSetBuf {
            buf: [
                char_to_slice(char_set.space),
                char_to_slice(char_set.newline),
                char_to_slice(char_set.lbox),
                char_to_slice(char_set.rbox),
                char_to_slice(char_set.colon),
                char_to_slice(char_set.hbar),
                char_to_slice(char_set.vbar),
                char_to_slice(char_set.xbar),
                char_to_slice(char_set.vbar_break),
                char_to_slice(char_set.vbar_gap),
                char_to_slice(char_set.uarrow),
                char_to_slice(char_set.rarrow),
                char_to_slice(char_set.ltop),
                char_to_slice(char_set.mtop),
                char_to_slice(char_set.rtop),
                char_to_slice(char_set.lbot),
                char_to_slice(char_set.mbot),
                char_to_slice(char_set.rbot),
                char_to_slice(char_set.lcross),
                char_to_slice(char_set.rcross),
                char_to_slice(char_set.underbar),
                char_to_slice(char_set.underline),
                char_to_slice(char_set.ellipsis),
            ],
        }
    }
}

impl Default for Report<'_> {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for Report<'_> {
    fn drop(&mut self) {
        unsafe {
            ffi::mu_delete(self.ptr);
        }
    }
}

/// Calculate the display width of a string (simple ASCII version).
/// For full Unicode support, consider using the unicode-width crate.
fn unicode_width(s: &str) -> i32 {
    s.chars().count() as i32
}

#[cfg(test)]
mod tests {
    use super::*;
    use insta::assert_snapshot;

    fn remove_trailing_whitespace(s: &str) -> String {
        s.lines()
            .map(|line| line.trim_end())
            .collect::<Vec<&str>>()
            .join("\n")
    }

    #[test]
    fn test_basic_report() {
        let mut report = Report::new()
            .with_source(("let x = 42;", "test.rs"))
            .with_config(Config::new().with_char_set_ascii().with_color_disabled())
            .with_title(Level::Error, "Test error")
            .with_code("E001")
            .with_label(0..3usize)
            .with_message("this is a test");

        let output = report.render_to_string(0, 0);
        assert!(!output.is_empty());
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            [E001] Error: Test error
               ,-[ test.rs:1:1 ]
               |
             1 | let x = 42;
               | ^|^
               |  `--- this is a test
            ---'
            "##
        );
    }

    #[test]
    fn test_config() {
        let config = Config::new()
            .with_compact(true)
            .with_char_set_ascii()
            .with_color_disabled();

        let mut report = Report::new()
            .with_config(config)
            .with_source(("hello", "test.rs"))
            .with_title(Level::Warning, "Test warning")
            .with_label(0..5usize)
            .with_message("test");

        let output = report.render_to_string(0, 0);
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Warning: Test warning
               ,-[ test.rs:1:1 ]
             1 |hello
               |  `--- test
            "##
        );
    }

    #[test]
    fn test_custom_level() {
        let mut report = Report::new()
            .with_config(Config::new().with_color_disabled())
            .with_source(("code", "test.rs"))
            .with_title("Hint", "Consider this")
            .with_label(0..4usize)
            .with_message("here");

        let output = report.render_to_string(0, 0);
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Hint: Consider this
               ╭─[ test.rs:1:1 ]
               │
             1 │ code
               │ ──┬─
               │   ╰─── here
            ───╯
            "##
        );
    }

    #[test]
    fn test_multiple_sources() {
        let mut report = Report::new()
            .with_config(Config::new().with_color_disabled())
            .with_source(("import foo", "main.rs")) // src_id = 0
            .with_source(("pub fn foo() {}", "foo.rs")) // src_id = 1
            .with_title(Level::Error, "Import error")
            .with_label((7..10, 0usize))
            .with_message("imported here")
            .with_label((7..10, 1usize))
            .with_message("defined here");

        let output = report.render_to_string(7, 0);
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Error: Import error
               ╭─[ main.rs:1:8 ]
               │
             1 │ import foo
               │        ─┬─
               │         ╰─── imported here
               │
               │─[ foo.rs:1:8 ]
               │
             1 │ pub fn foo() {}
               │        ─┬─
               │         ╰─── defined here
            ───╯
            "##
        );
    }

    #[test]
    fn test_source_new() {
        let mut report = Report::new()
            .with_config(Config::new().with_color_disabled())
            .with_source(Source::new("test code", "file.rs"))
            .with_title(Level::Error, "Error")
            .with_label((0..4, 0usize))
            .with_message("here");

        let output = report.render_to_string(0, 0);
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Error: Error
               ╭─[ file.rs:1:1 ]
               │
             1 │ test code
               │ ──┬─
               │   ╰─── here
            ───╯
            "##
        );
    }

    #[test]
    fn test_label_at() {
        let mut report = Report::new()
            .with_config(Config::new().with_color_disabled())
            .with_source(("code1", "a.rs"))
            .with_source(("code2", "b.rs"))
            .with_title(Level::Error, "Error")
            .with_label((0..4, 0usize))
            .with_message("in a")
            .with_label((0..4, 1usize))
            .with_message("in b");

        let output = report.render_to_string(0, 0);
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Error: Error
               ╭─[ a.rs:1:1 ]
               │
             1 │ code1
               │ ──┬─
               │   ╰─── in a
               │
               │─[ b.rs:1:1 ]
               │
             1 │ code2
               │ ──┬─
               │   ╰─── in b
            ───╯
            "##
        );
    }

    #[test]
    fn test_custom_charset() {
        // Custom charset with different characters
        let custom = CharSet {
            hbar: '=',
            vbar: '!',
            ltop: '<',
            rtop: '>',
            lbot: '[',
            rbot: ']',
            ..CharSet::ascii()
        };

        let config = Config::new().with_char_set(&custom).with_color_disabled();

        let mut report = Report::new()
            .with_config(config)
            .with_source(("hello", "test.rs"))
            .with_title(Level::Error, "Test")
            .with_label(0..5usize)
            .with_message("here");

        let output = report.render_to_string(0, 0);
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Error: Test
               <=[ test.rs:1:1 ]
               !
             1 ! hello
               ! ^^|^^
               !   [==== here
            ===]
            "##
        );
    }

    #[test]
    fn test_custom_color() {
        struct CustomColor;
        impl Color for CustomColor {
            fn color(&self, w: &mut dyn Write, kind: ColorKind) -> std::io::Result<()> {
                match kind {
                    ColorKind::Reset => w.write(b"}")?,
                    _ => w.write(b"{")?,
                };
                Ok(())
            }
        }

        let mut report = Report::new()
            .with_config(Config::new().with_char_set_ascii().with_color(&CustomColor))
            .with_source(("klmnop", "<unknown>"))
            .with_title(Level::Error, "test colors")
            .with_label(0..6usize)
            .with_message("here");

        let output = report.render_to_string(0, 0);
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            {Error:} test colors
               {,-[} <unknown>:1:1 {]}
               {|}
             {1 |} {klmnop}
               {|} {^^^|^^}
               {|}    {`----} here
            {---'}
            "##
        );
    }

    #[test]
    fn test_custom_label_color() {
        struct CustomColor;
        impl Color for CustomColor {
            fn color(&self, w: &mut dyn Write, kind: ColorKind) -> std::io::Result<()> {
                match kind {
                    ColorKind::Reset => w.write(b"}").map(|_| ()),
                    _ => w.write(b"{").map(|_| ()),
                }
            }
        }

        let mut report = Report::new()
            .with_config(Config::new().with_char_set_ascii().with_color_disabled())
            .with_source(("abcdef", "<unknown>"))
            .with_title(Level::Error, "test label colors")
            .with_label(0..6usize)
            .with_color(&CustomColor)
            .with_message("here");

        let output = report.render_to_string(0, 0);
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Error: test label colors
               ,-[ <unknown>:1:1 ]
               |
             1 | {abcdef}
               | {^^^|^^}
               |    {`----} here
            ---'
            "##
        );
    }

    #[test]
    fn test_source_with_line_offset() {
        let mut report = Report::new()
            .with_config(Config::new().with_color_disabled())
            .with_source(
                Source::new("some code here", "file.rs").with_line_offset(99), // Line numbers start at 100
            )
            .with_title(Level::Error, "Error")
            .with_label(0..4usize)
            .with_message("here");

        let output = report.render_to_string(0, 0);
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Error: Error
                 ╭─[ file.rs:100:1 ]
                 │
             100 │ some code here
                 │ ──┬─
                 │   ╰─── here
            ─────╯
            "##
        );
    }
}
