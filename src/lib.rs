//! Safe Rust wrapper for musubi diagnostic renderer
//!
//! This library provides a safe, ergonomic Rust API for the musubi C library,
//! which renders beautiful diagnostic messages similar to rustc and other modern compilers.
//!
//! # Quick Start
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
//! println!("{}", report.render_to_string(0, 0).unwrap());
//! ```
//!
//! # Core Concepts
//!
//! ## Sources
//!
//! A [`Source`] provides the text content for diagnostics. Sources can be:
//! - In-memory strings: `report.with_source(("code", "file.rs"))`
//! - Custom implementations of the [`Source`] trait for lazy loading or special formatting
//!
//! Sources are registered in order and assigned IDs: first source is ID 0, second is ID 1, etc.
//!
//! ## Labels
//!
//! Labels highlight specific spans in your source code. Each label can have:
//! - A span (byte or character range)
//! - A message explaining the issue
//! - Custom colors
//! - Display order and priority
//!
//! ```rust
//! # use musubi::{Report, Level};
//! let mut report = Report::new()
//!     .with_source(("let x = 42;", "test.rs"))
//!     .with_title(Level::Error, "Type mismatch")
//!     .with_label(0..3)     // First label
//!     .with_message("expected type here")
//!     .with_label(4..5)     // Second label
//!     .with_message("found here");
//! ```
//!
//! ## Configuration
//!
//! Customize rendering with [`Config`]:
//! - Character sets (ASCII vs Unicode)
//! - Color schemes
//! - Layout options (compact mode, tab width, line wrapping)
//! - Label attachment (start/middle/end of spans)
//!
//! ```rust
//! # use musubi::{Report, Config, CharSet};
//! let config = Config::new()
//!     .with_char_set_unicode()     // Use box-drawing characters
//!     .with_color_default()        // Enable ANSI colors
//!     .with_compact(true)          // Compact output
//!     .with_tab_width(4);          // 4-space tabs
//!
//! let mut report = Report::new()
//!     .with_config(config);
//! ```
//!
//! ## Multiple Sources
//!
//! Display diagnostics that span multiple files:
//!
//! ```rust
//! # use musubi::{Report, Level};
//! let mut report = Report::new()
//!     .with_source(("import foo", "main.rs"))      // Source ID 0
//!     .with_source(("pub fn foo() {}", "lib.rs")) // Source ID 1
//!     .with_title(Level::Error, "Import error")
//!     .with_label((7..10, 0))  // Label in main.rs
//!     .with_message("imported here")
//!     .with_label((7..10, 1))  // Label in lib.rs
//!     .with_message("defined here");
//! ```
//!
//! ## Custom Colors
//!
//! Implement the [`Color`] trait to provide custom color schemes:
//!
//! ```rust
//! # use musubi::{Config, Color, ColorKind};
//! # use std::io::Write;
//! struct MyColors;
//!
//! impl Color for MyColors {
//!     fn color(&self, w: &mut dyn Write, kind: ColorKind) -> std::io::Result<()> {
//!         match kind {
//!             ColorKind::Error => write!(w, "\x1b[31m"),    // Red
//!             ColorKind::Warning => write!(w, "\x1b[33m"),  // Yellow
//!             ColorKind::Reset => write!(w, "\x1b[0m"),     // Reset
//!             _ => Ok(()),
//!         }
//!     }
//! }
//!
//! let config = Config::new().with_color(&MyColors);
//! ```
//!
//! ## Custom Sources
//!
//! Implement the [`Source`] trait for lazy file loading or special formatting:
//!
//! ```rust
//! # use musubi::{Source, Line};
//! # use std::io;
//! struct LazyFileSource {
//!     // ... your fields
//! }
//!
//! impl Source for LazyFileSource {
//!     fn init(&mut self) -> io::Result<()> {
//!         // Initialize (e.g., open file, read metadata)
//!         Ok(())
//!     }
//!
//!     fn get_line(&self, line_no: usize) -> &[u8] {
//!         // Return the requested line
//! #       b""
//!     }
//!
//!     fn get_line_info(&self, line_no: usize) -> Line {
//!         // Return line metadata (offsets, lengths)
//! #       Line::default()
//!     }
//!
//!     fn line_for_chars(&self, char_pos: usize) -> (usize, Line) {
//!         // Map character position to line
//! #       (0, Line::default())
//!     }
//!
//!     fn line_for_bytes(&self, byte_pos: usize) -> (usize, Line) {
//!         // Map byte position to line
//! #       (0, Line::default())
//!     }
//! }
//! ```
//!
//! # Lifetime Management
//!
//! All string references passed to the report must outlive the report itself.
//! This enables zero-copy operation:
//!
//! ```rust
//! # use musubi::{Report, Level};
//! let code = String::from("let x = 42;");
//! let mut report = Report::new()
//!     .with_source((code.as_str(), "test.rs"))
//!     .with_title(Level::Error, "Error");
//!
//! // code must remain valid until report is rendered
//! let output = report.render_to_string(0, 0).unwrap();
//! // now code can be dropped
//! ```

mod ffi;

use std::ffi::{c_char, c_int, c_void};
use std::fmt::Debug;
use std::io::{self, Write};
use std::marker::PhantomData;
use std::mem::MaybeUninit;
use std::ptr::{self, null_mut};

/// Diagnostic severity level
///
/// Represents the severity of a diagnostic message.
/// These levels affect both the visual styling (colors, icons)
/// and semantic meaning of the diagnostic.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    /// Error level - indicates a compilation/execution failure
    Error,
    /// Warning level - indicates a potential problem
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
///
/// Controls where the label's arrow/message attaches to the highlighted span.
/// This affects the visual positioning of the label annotation.
///
/// # Example
/// ```text
/// Middle (default):
///   foo(bar, baz)
///       ---^---
///          |
///          label here
///
/// Start:
///   foo(bar, baz)
///       ^-------
///       |
///       label here
///
/// End:
///   foo(bar, baz)
///       -------^
///              |
///              label here
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LabelAttach {
    /// Attach in the middle of the span (default)
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
///
/// Determines how span ranges are interpreted:
/// - [`Byte`](IndexType::Byte) - Positions are byte offsets (faster, ASCII-friendly)
/// - [`Char`](IndexType::Char) - Positions are character offsets (UTF-8 aware, default)
///
/// # Example
/// ```text
/// Source: "你好"  (2 characters, 6 bytes in UTF-8)
///
/// With IndexType::Char:
///   span 0..1 selects "你"
///   span 1..2 selects "好"
///
/// With IndexType::Byte:
///   span 0..3 selects "你" (3 bytes)
///   span 3..6 selects "好" (3 bytes)
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum IndexType {
    /// Index by byte offset (0-indexed)
    Byte,
    /// Index by character offset (0-indexed, UTF-8 aware, default)
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
///
/// Each category represents a different part of the diagnostic rendering
/// that can be styled independently.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ColorKind {
    /// Reset all colors/styles to default
    Reset,
    /// Error severity level and error-related elements
    Error,
    /// Warning severity level and warning-related elements
    Warning,
    /// Custom severity level names (e.g., "Hint", "Note")
    Kind,
    /// Line number margin (gutter)
    Margin,
    /// Margin for skipped lines ("...")
    SkippedMargin,
    /// Less important text (e.g., source file paths)
    Unimportant,
    /// Note and help messages
    Note,
    /// Label highlights and arrows
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

/// A label span with optional source ID.
///
/// The `src_id` is the registration order of sources (0 for first, 1 for second, etc.).
///
/// This enables flexible label creation:
/// - `.with_label_at((0..10, 0))` - tuple of (range, src_id)
#[derive(Debug, Clone, Copy)]
pub struct LabelSpan {
    start: usize,
    end: usize,
    src_id: ffi::mu_Id,
}

/// Range
impl From<std::ops::Range<usize>> for LabelSpan {
    fn from(value: std::ops::Range<usize>) -> Self {
        LabelSpan {
            start: value.start,
            end: value.end,
            src_id: 0.into(),
        }
    }
}

impl From<std::ops::Range<i32>> for LabelSpan {
    fn from(value: std::ops::Range<i32>) -> Self {
        LabelSpan {
            start: value.start.max(0) as usize,
            end: value.end.max(0) as usize,
            src_id: 0.into(),
        }
    }
}

/// (Range, usize) tuple
impl<SrcId: Into<ffi::mu_Id>> From<(std::ops::Range<usize>, SrcId)> for LabelSpan {
    fn from(value: (std::ops::Range<usize>, SrcId)) -> Self {
        LabelSpan {
            start: value.0.start,
            end: value.0.end,
            src_id: value.1.into(),
        }
    }
}

/// (Range, usize) tuple
impl<SrcId: Into<ffi::mu_Id>> From<(std::ops::Range<i32>, SrcId)> for LabelSpan {
    fn from(value: (std::ops::Range<i32>, SrcId)) -> Self {
        LabelSpan {
            start: value.0.start.max(0) as usize,
            end: value.0.end.max(0) as usize,
            src_id: value.1.into(),
        }
    }
}

/// Character set for rendering diagnostic output
///
/// Defines all the box-drawing and decorative characters used in rendering.
/// Two predefined sets are available:
/// - [`CharSet::ascii()`] - Uses ASCII characters (`-`, `|`, `+`, etc.)
/// - [`CharSet::unicode()`] - Uses Unicode box-drawing characters (`─`, `│`, `┬`, etc.)
///
/// You can also create custom character sets by modifying individual fields.
///
/// # Example
/// ```rust
/// # use musubi::CharSet;
/// let custom = CharSet {
///     hbar: '=',
///     vbar: '!',
///     ..CharSet::ascii()
/// };
/// ```
#[derive(Default, Debug, Clone, Copy, PartialEq, Eq)]
pub struct CharSet {
    /// Space character (usually ' ')
    pub space: char,
    /// Newline representation (usually visible as box character)
    pub newline: char,
    /// Left box bracket (e.g., '[')
    pub lbox: char,
    /// Right box bracket (e.g., ']')
    pub rbox: char,
    /// Colon separator (e.g., ':')
    pub colon: char,
    /// Horizontal bar (e.g., '-' or '─')
    pub hbar: char,
    /// Vertical bar (e.g., '|' or '│')
    pub vbar: char,
    /// Cross bar (both horizontal and vertical)
    pub xbar: char,
    /// Vertical bar with break
    pub vbar_break: char,
    /// Vertical bar with gap
    pub vbar_gap: char,
    /// Upward arrow (e.g., '^' or '↑')
    pub uarrow: char,
    /// Rightward arrow (e.g., '>' or '→')
    pub rarrow: char,
    /// Left top corner (e.g., ',' or '╭')
    pub ltop: char,
    /// Middle top connector (e.g., '^' or '┬')
    pub mtop: char,
    /// Right top corner (e.g., '.' or '╮')
    pub rtop: char,
    /// Left bottom corner (e.g., '`' or '╰')
    pub lbot: char,
    /// Middle bottom connector (e.g., 'v' or '┴')
    pub mbot: char,
    /// Right bottom corner (e.g., '\'' or '╯')
    pub rbot: char,
    /// Left cross connector (e.g., '+' or '├')
    pub lcross: char,
    /// Right cross connector (e.g., '+' or '┤')
    pub rcross: char,
    /// Underbar character (e.g., '_' or '─')
    pub underbar: char,
    /// Underline character for emphasis
    pub underline: char,
    /// Ellipsis for truncated text (e.g., '...' or '…')
    pub ellipsis: char,
}

impl From<*const ffi::mu_Charset> for CharSet {
    #[allow(clippy::not_unsafe_ptr_arg_deref)]
    fn from(ptr: *const ffi::mu_Charset) -> Self {
        fn slice_to_char(s: *const c_char) -> char {
            if s.is_null() {
                return ' ';
            }
            // SAFETY: Pointer is from C library, null-checked above.
            // Length is stored in first byte, followed by valid UTF-8 data.
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
        // SAFETY: ptr is passed by calleree and assumed to be valid
        let chars = unsafe { &*ptr };
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

impl CharSet {
    /// Predefined ASCII character set
    pub fn ascii() -> CharSet {
        // SAFETY: mu_ascii() returns a valid static charset pointer
        unsafe { ffi::mu_ascii() }.into()
    }

    /// Predefined Unicode character set
    pub fn unicode() -> CharSet {
        // SAFETY: mu_unicode() returns a valid static charset pointer
        unsafe { ffi::mu_unicode() }.into()
    }
}

/// Automatic color generator for creating visually distinct label colors.
///
/// ColorGenerator produces a sequence of pseudo-random colors that are
/// perceptually distinct and readable. It's useful for assigning colors to
/// multiple labels automatically.
///
/// # Examples
///
/// ```rust
/// use musubi::{Report, ColorGenerator, Level};
///
/// let mut cg = ColorGenerator::new();
/// let mut report = Report::new()
///     .with_source(("let x = 1;", "test.rs"))
///     .with_title(Level::Error, "Multiple labels")
///     .with_label(0..3)
///     .with_color(&cg.next_color())  // First color
///     .with_label(4..5)
///     .with_color(&cg.next_color()); // Second color (different)
/// ```
pub struct ColorGenerator {
    base: ffi::mu_ColorGen,
}

/// Trait for types that can be used as raw color codes.
///
/// This trait is implemented for [`GenColor`] returned by [`ColorGenerator::next_color`].
/// It allows efficiently passing pre-generated color codes to labels without
/// the overhead of trait objects.
pub trait IntoColor {
    /// Apply this color to the most recently added label in the report.
    ///
    /// This method is called internally by [`Report::with_color`].
    fn into_color(self, report: &mut Report);
}

/// A pre-generated ANSI color code.
///
/// This type wraps a raw color code buffer generated by [`ColorGenerator`].
/// It can be applied to labels using [`Report::with_color`].
///
/// # Note
///
/// GenColor is more efficient than trait-object based colors because it
/// avoids dynamic dispatch and stores the color code directly.
pub struct GenColor(ffi::mu_ColorCode);

impl IntoColor for &GenColor {
    fn into_color(self, report: &mut Report) {
        // SAFETY: mu_fromcolorcode is a valid C callback that reads from the color code array.
        // The pointer to self.0 is valid for the duration of the mu_color call.
        unsafe {
            ffi::mu_color(
                report.ptr,
                Some(ffi::mu_fromcolorcode),
                self.0.as_ptr() as *mut c_void,
            );
        }
    }
}

impl Default for ColorGenerator {
    fn default() -> Self {
        Self::new()
    }
}

impl ColorGenerator {
    /// Create a new color generator with default brightness.
    pub fn new() -> Self {
        Self::new_with_brightness(0.5)
    }

    /// Create a new color generator with the specified brightness.
    pub fn new_with_brightness(brightness: f32) -> Self {
        let mut obj = MaybeUninit::uninit();
        // SAFETY: mu_initcolorgen initializes all fields of the color generator
        unsafe { ffi::mu_initcolorgen(obj.as_mut_ptr(), brightness) };
        Self {
            // SAFETY: obj has been fully initialized by mu_initcolorgen above
            base: unsafe { obj.assume_init() },
        }
    }

    /// Generate the next color in the sequence.
    ///
    /// Each call returns a different color code that is visually distinct from
    /// previous colors. The sequence is deterministic based on the initial state.
    ///
    /// # Examples
    ///
    /// ```rust
    /// use musubi::ColorGenerator;
    ///
    /// let mut cg = ColorGenerator::new();
    /// let color1 = cg.next_color();
    /// let color2 = cg.next_color();  // Different from color1
    /// let color3 = cg.next_color();  // Different from color1 and color2
    /// ```
    pub fn next_color(&mut self) -> GenColor {
        let mut rc = GenColor([0; ffi::MU_COLOR_CODE_SIZE]);
        // SAFETY: &mut self ensures exclusive access to base.
        // mu_gencolor always succeeds and fills the color code array.
        unsafe { ffi::mu_gencolor(&mut self.base, &mut rc.0) };
        rc
    }
}

/// Trait for types that can provide color codes.
///
/// Similar to `Display`, this trait allows custom color implementations
/// without heap allocation.
///
/// # Example
/// ```rust
/// # use musubi::{Config, ColorKind, Color};
/// # use std::io::Write;
/// struct MyColors;
///
/// impl Color for MyColors {
///     fn color(&self, w: &mut dyn Write, kind: ColorKind) -> std::io::Result<()> {
///         match kind {
///             ColorKind::Error => w.write(b"[")?,
///             ColorKind::Reset => w.write(b"]")?,
///             _ => 0,
///         };
///         Ok(())
///     }
/// }
///
/// Config::new().with_color(&MyColors);
/// ```
pub trait Color {
    /// Generate ANSI color code for the given color kind.
    ///
    /// This method is called during rendering to produce color escape sequences.
    /// Write the ANSI escape sequence (e.g., `\x1b[31m` for red) to `w`.
    ///
    /// # Arguments
    ///
    /// * `w` - Output writer for the color code
    /// * `kind` - The type of color needed (Error, Warning, etc.)
    ///
    /// # Returns
    ///
    /// `Ok(())` on success, or an I/O error if writing fails.
    fn color(&self, w: &mut dyn Write, kind: ColorKind) -> std::io::Result<()>;
}

/// Internal userdata structure for color callbacks.
///
/// This structure is passed to C color callback functions via the `ud` pointer.
/// It contains:
/// - A type-erased pointer to the Rust `Color` trait object
/// - A pointer to the shared color buffer for ANSI escape code output
///
/// # Safety
///
/// The pointers must remain valid for the entire duration of rendering.
/// Memory safety is ensured by storing Color references and the buffer
/// in the Report structure with appropriate lifetimes.
struct ColorUd {
    /// Pointer to the Color trait object (type-erased for FFI)
    color_obj: *const c_void,
    /// Pointer to the shared buffer for color escape codes
    color_buf: *mut [u8; ffi::MU_COLOR_CODE_SIZE],
}

impl<C: Color> IntoColor for &C {
    fn into_color(self, report: &mut Report) {
        report.color_uds.push(Box::new(ColorUd {
            color_obj: self as *const _ as *const c_void,
            color_buf: &mut report.color_buf,
        }));
        extern "C" fn color_fn<C: Color>(
            ud: *mut c_void,
            kind: ffi::mu_ColorKind,
        ) -> ffi::mu_Chunk {
            // SAFETY: ud is a valid ColorUd pointer from color_uds vector
            let ud = unsafe { &mut *(ud as *mut ColorUd) };
            // SAFETY: color_obj points to a valid C reference with lifetime 'a
            let color = unsafe { &*(ud.color_obj as *const C) };
            // SAFETY: color_buf points to Report.color_buf, valid during render
            let buf = unsafe { &mut *ud.color_buf };
            let mut remain = &mut buf[1..];
            match color.color(&mut remain, ColorKind::from_ffi(kind)) {
                Ok(_) => {
                    let used = (ffi::MU_COLOR_CODE_SIZE - remain.len() - 1) as u8;
                    buf[0] = used;
                    buf.as_ptr() as *const c_char
                }
                Err(_) => c"".as_ptr(),
            }
        }
        // SAFETY: self.ptr is valid, color_fn has correct signature, ud points to valid ColorUd
        unsafe {
            ffi::mu_color(
                report.ptr,
                Some(color_fn::<C>),
                &**report.color_uds.last().unwrap() as *const ColorUd as *mut c_void,
            )
        };
    }
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
            .field("column_order", &self.inner.column_order)
            .field("align_messages", &self.inner.align_messages)
            .field("multiline_arrows", &self.inner.multiline_arrows)
            .field("tab_width", &self.inner.tab_width)
            .field("limit_width", &self.inner.limit_width)
            .field("ambi_width", &self.inner.ambi_width)
            .field("label_attach", &self.inner.label_attach)
            .field("index_type", &self.inner.index_type)
            .finish()
    }
}

impl Clone for Config<'_> {
    fn clone(&self) -> Self {
        // SAFETY: mu_Config is a C struct with no Drop semantics, safe to copy
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
        // SAFETY: mu_initconfig initializes all fields of the config struct
        unsafe {
            ffi::mu_initconfig(obj.as_mut_ptr());
        }
        Self {
            // SAFETY: obj has been fully initialized by mu_initconfig above
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
    ///
    /// When enabled, vertical bars between labels are drawn with gaps
    /// for better visual clarity when labels overlap.
    ///
    /// Default: depends on C library default
    pub fn with_cross_gap(mut self, enabled: bool) -> Self {
        self.inner.cross_gap = enabled as c_int;
        self
    }

    /// Enable or disable compact mode.
    ///
    /// In compact mode, the diagnostic output is more condensed:
    /// - Underlines and arrows may be merged onto the same line
    /// - Only meaningful label arrows are shown
    ///
    /// Works with underlines enabled or disabled.
    ///
    /// Default: `false`
    pub fn with_compact(mut self, enabled: bool) -> Self {
        self.inner.compact = enabled as c_int;
        self
    }

    /// Enable or disable underlines for highlighted spans.
    ///
    /// When enabled, spans are underlined with characters like `^^^`.
    /// When disabled, only label arrows are shown.
    ///
    /// Works with both compact and non-compact modes.
    ///
    /// Default: `true`
    pub fn with_underlines(mut self, enabled: bool) -> Self {
        self.inner.underlines = enabled as c_int;
        self
    }

    /// Enable or disable natural label ordering.
    ///
    /// When disabled (default), labels are sorted to minimize line crossings:
    /// - Inline labels appear first, ordered by reverse column position
    /// - Multi-line labels follow, with tails before heads
    ///
    /// When enabled, labels are simply sorted by column position.
    ///
    /// Default: `false` (natural ordering enabled)
    ///
    /// # Example
    /// ```rust
    /// # use musubi::Config;
    /// let config = Config::new().with_column_order(true);  // Simple column order
    /// ```
    pub fn with_column_order(mut self, enabled: bool) -> Self {
        self.inner.column_order = enabled as c_int;
        self
    }

    /// Enable or disable aligned label messages.
    ///
    /// When enabled (default), label messages are aligned to the same column,
    /// producing a more structured appearance with longer arrows.
    ///
    /// When disabled, messages are placed immediately after their arrows,
    /// creating more compact output.
    ///
    /// Default: `true` (aligned)
    ///
    /// # Example
    /// ```rust
    /// # use musubi::Config;
    /// let config = Config::new().with_align_messages(false);  // Compact arrows
    /// ```
    pub fn with_align_messages(mut self, enabled: bool) -> Self {
        self.inner.align_messages = enabled as c_int;
        self
    }

    /// Enable or disable multiline arrows for labels.
    ///
    /// When enabled, labels that span multiple lines will have
    /// arrows drawn across all covered lines.
    ///
    /// Default: `true`
    pub fn with_multiline_arrows(mut self, enabled: bool) -> Self {
        self.inner.multiline_arrows = enabled as c_int;
        self
    }

    /// Set the tab width for rendering.
    ///
    /// Tab characters (`\t`) in source code are expanded to this many spaces.
    ///
    /// Default: `4`
    ///
    /// # Example
    /// ```rust
    /// # use musubi::Config;
    /// let config = Config::new().with_tab_width(8);  // 8-space tabs
    /// ```
    pub fn with_tab_width(mut self, width: i32) -> Self {
        self.inner.tab_width = width;
        self
    }

    /// Set the width limit for line wrapping.
    ///
    /// Lines longer than this width will be truncated with an ellipsis.
    /// Set to `0` for no limit (lines can be arbitrarily long).
    ///
    /// Default: `0` (no limit)
    ///
    /// # Example
    /// ```rust
    /// # use musubi::Config;
    /// let config = Config::new().with_limit_width(80);  // Wrap at 80 columns
    /// ```
    pub fn with_limit_width(mut self, width: i32) -> Self {
        self.inner.limit_width = width;
        self
    }

    /// Set the ambiguous character width.
    ///
    /// Some Unicode characters have ambiguous width (e.g., East Asian characters).
    /// This setting determines their display width:
    /// - `1` - Treat as narrow (1 column)
    /// - `2` - Treat as wide (2 columns)
    ///
    /// Default: `1`
    ///
    /// # Example
    /// ```rust
    /// # use musubi::Config;
    /// let config = Config::new().with_ambi_width(2);  // East Asian width
    /// ```
    pub fn with_ambi_width(mut self, width: i32) -> Self {
        self.inner.ambi_width = width;
        self
    }

    /// Set where labels attach to spans.
    ///
    /// Controls the default attachment point for all labels.
    /// Individual labels can override this with [`Report::with_order`].
    ///
    /// Default: [`LabelAttach::Middle`]
    pub fn with_label_attach(mut self, attach: LabelAttach) -> Self {
        self.inner.label_attach = attach.into();
        self
    }

    /// Set the index type (character or byte).
    ///
    /// Determines how span ranges are interpreted.
    /// See [`IndexType`] for details.
    ///
    /// Default: [`IndexType::Char`]
    pub fn with_index_type(mut self, index_type: IndexType) -> Self {
        self.inner.index_type = index_type.into();
        self
    }

    /// Set ASCII character set for rendering.
    ///
    /// Uses ASCII characters (`-`, `|`, `+`, etc.) for box drawing.
    /// This is compatible with all terminals and file formats.
    ///
    /// # Example
    /// ```text
    /// Error: message
    ///    ,-[ file.rs:1:1 ]
    ///    |
    ///  1 | code here
    ///    | ^^^^
    ///    | |
    ///    | `--- label
    /// ---'
    /// ```
    pub fn with_char_set_ascii(mut self) -> Self {
        // SAFETY: mu_ascii() returns a valid static charset pointer
        self.inner.char_set = unsafe { ffi::mu_ascii() };
        self.char_set = None;
        self
    }

    /// Set Unicode character set for rendering.
    ///
    /// Uses Unicode box-drawing characters (─, │, ┬, etc.) for prettier output.
    /// Requires a terminal that supports Unicode.
    ///
    /// # Example
    /// ```text
    /// Error: message
    ///    ╭─[ file.rs:1:1 ]
    ///    │
    ///  1 │ code here
    ///    │ ────
    ///    │ │
    ///    │ ╰─── label
    /// ───╯
    /// ```
    pub fn with_char_set_unicode(mut self) -> Self {
        // SAFETY: mu_unicode() returns a valid static charset pointer
        self.inner.char_set = unsafe { ffi::mu_unicode() };
        self.char_set = None;
        self
    }

    /// Set a custom character set for rendering.
    ///
    /// Allows fine-grained control over all box-drawing characters.
    /// The character set must outlive the config.
    ///
    /// # Example
    /// ```rust
    /// # use musubi::{Config, CharSet};
    /// let custom = CharSet {
    ///     hbar: '=',
    ///     vbar: '!',
    ///     ..CharSet::ascii()
    /// };
    /// let config = Config::new().with_char_set(&custom);
    /// ```
    pub fn with_char_set(mut self, char_set: &'a CharSet) -> Self {
        self.char_set = Some(char_set);
        self
    }

    /// Enable default ANSI colors.
    ///
    /// Uses the built-in color scheme with standard ANSI escape codes:
    /// - Errors in red
    /// - Warnings in yellow
    /// - Margins in blue
    /// - etc.
    ///
    /// This is appropriate for terminal output.
    pub fn with_color_default(mut self) -> Self {
        self.inner.color = Some(ffi::mu_default_color);
        self.color_ud = None;
        self
    }

    /// Disable color output.
    ///
    /// All output will be plain text without ANSI escape codes.
    /// This is appropriate for file output or non-color terminals.
    ///
    /// Default: colors are disabled
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
            // SAFETY: ud is provided by the caller and assumed valid
            let ud = unsafe { &mut *(ud as *mut ColorUd) };
            // SAFETY: in color_fn's call lifetime, color_obj and color_buf are valid
            let color = unsafe { &*(ud.color_obj as *const C) };
            // SAFETY: color_buf is initialized by Report::render_to_writer and remains valid during callback
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
/// ```rust
/// # use musubi::{Source, Line};
/// # use std::default::Default;
///
/// // implement a custom source
/// struct MySource {}
///
/// # impl MySource { fn new() -> Self { Self{} } }
///
/// impl Source for MySource {
///     // ...
/// # fn init(&mut self) -> std::io::Result<()> { Ok(()) }
/// # fn get_line(&self, line_no: usize) -> &[u8] { b"" }
/// # fn get_line_info(&self, line_no: usize) -> musubi::Line { Line::new() }
/// # fn line_for_chars(&self, char_pos: usize) -> (usize, musubi::Line) { (0, Line::new()) }
/// # fn line_for_bytes(&self, byte_pos: usize) -> (usize, musubi::Line) { (0, Line::new()) }
/// }
///
/// let mut report = musubi::Report::new()
///     // use tuple syntax to specific source code in memory with Report
///     .with_source(("let x = 42;", "main.rs"))
///
///     // use a custom source implementing the Source trait
///     .with_source((MySource::new(), "my_source.rs"));
/// ```
pub trait Source {
    /// Initialize the source (e.g., read lines).
    fn init(&mut self) -> io::Result<()>;

    /// Get a specific line by line number (0-based).
    /// Return last line data if line_no is out of range.
    fn get_line(&self, line_no: usize) -> &[u8];

    /// Get line info struct by line number (0-based).
    /// Return last line info if line_no is out of range.
    fn get_line_info(&self, line_no: usize) -> Line;

    /// Get the line number and line info for a given character position.
    /// Return last line number and info if char_pos is out of range.
    fn line_for_chars(&self, char_pos: usize) -> (usize, Line);

    /// Get the line number and line info for a given byte position.
    /// Return last line number and info if byte_pos is out of range.
    fn line_for_bytes(&self, byte_pos: usize) -> (usize, Line);
}

/// Information about a line in source code.
///
/// This structure describes a line's position and length in both
/// character and byte offsets, which is important for proper UTF-8 handling.
///
/// Returned by [`Source`] trait methods to provide line metadata.
#[derive(Default, Debug, Clone, Copy)]
pub struct Line {
    /// Character offset from the start of the source (0-based)
    pub offset: usize,
    /// Byte offset from the start of the source (0-based)
    pub byte_offset: usize,
    /// Line length in characters (excluding newline)
    pub len: u32,
    /// Line length in bytes (excluding newline)
    pub byte_len: u32,
    /// Newline sequence length in bytes (0, 1 for \n, 2 for \r\n)
    pub newline: u32,
}

impl Line {
    /// Create a new empty Line with all fields set to zero.
    pub fn new() -> Self {
        Self::default()
    }
}

impl From<*const ffi::mu_Line> for Line {
    #[allow(clippy::not_unsafe_ptr_arg_deref)]
    fn from(line: *const ffi::mu_Line) -> Self {
        // SAFETY: line pointer is provided by C library and assumed valid
        let line = unsafe { &*line };
        Line {
            offset: line.offset,
            byte_offset: line.byte_offset,
            len: line.len,
            byte_len: line.byte_len,
            newline: line.newline,
        }
    }
}

impl From<Line> for ffi::mu_Line {
    fn from(line: Line) -> Self {
        ffi::mu_Line {
            offset: line.offset,
            byte_offset: line.byte_offset,
            len: line.len,
            byte_len: line.byte_len,
            newline: line.newline,
        }
    }
}

/// Trait for types that can be converted into source files for diagnostics.
///
/// This trait is implemented for common source types like `&str`, tuples of
/// `(&str, &str)` for (content, name), and tuples with line offsets.
///
/// You typically don't need to implement this trait manually - use the provided
/// implementations via [`Report::with_source`].
///
/// # Examples
///
/// ```
/// # use musubi::Report;
/// let mut report = Report::new()
///     .with_source("code content")              // &str
///     .with_source(("code", "file.rs"))        // (&str, &str)
///     .with_source(("code", "file.rs", 10));   // (&str, &str, i32) with line offset
/// ```
pub trait IntoSource {
    /// Convert this value into a C source pointer.
    ///
    /// This method is called internally by [`Report::with_source`].
    fn into_source(self, report: &mut Report) -> *mut ffi::mu_Source;
}

struct MemorySource<'a> {
    content: ffi::mu_Slice,
    name: ffi::mu_Slice,
    line_no_offset: c_int,
    _marker: PhantomData<&'a str>,
}

impl IntoSource for &str {
    fn into_source(self, report: &mut Report) -> *mut ffi::mu_Source {
        MemorySource {
            content: self.into(),
            name: Default::default(),
            line_no_offset: 0,
            _marker: PhantomData,
        }
        .into_source(report)
    }
}

impl<'a> IntoSource for (&'a str, &'a str) {
    fn into_source(self, report: &mut Report) -> *mut ffi::mu_Source {
        MemorySource {
            content: self.0.into(),
            name: self.1.into(),
            line_no_offset: 0,
            _marker: PhantomData,
        }
        .into_source(report)
    }
}

impl<'a> IntoSource for (&'a str, &'a str, i32) {
    fn into_source(self, report: &mut Report) -> *mut ffi::mu_Source {
        MemorySource {
            content: self.0.into(),
            name: self.1.into(),
            line_no_offset: self.2,
            _marker: PhantomData,
        }
        .into_source(report)
    }
}

impl<'a> IntoSource for MemorySource<'a> {
    fn into_source(self, report: &mut Report) -> *mut ffi::mu_Source {
        // SAFETY: report.ptr is a valid mu_Report pointer, content and name have valid lifetimes
        unsafe {
            let src = ffi::mu_memory_source(report.ptr, self.content, self.name);
            (*src).line_no_offset = self.line_no_offset;
            src
        }
    }
}

struct TraitSource<'a, S> {
    src: S,
    name: ffi::mu_Slice,
    line_no_offset: c_int,
    _marker: PhantomData<&'a str>,
}

impl<S: Source> IntoSource for S {
    fn into_source(self, report: &mut Report) -> *mut ffi::mu_Source {
        TraitSource {
            src: self,
            name: Default::default(),
            line_no_offset: 0,
            _marker: PhantomData,
        }
        .into_source(report)
    }
}

impl<S: Source> IntoSource for (S, &str) {
    fn into_source(self, report: &mut Report) -> *mut ffi::mu_Source {
        TraitSource {
            src: self.0,
            name: self.1.into(),
            line_no_offset: 0,
            _marker: PhantomData,
        }
        .into_source(report)
    }
}

impl<S: Source> IntoSource for (S, &str, i32) {
    fn into_source(self, report: &mut Report) -> *mut ffi::mu_Source {
        TraitSource {
            src: self.0,
            name: self.1.into(),
            line_no_offset: self.2,
            _marker: PhantomData,
        }
        .into_source(report)
    }
}

impl<S: Source> IntoSource for TraitSource<'_, S> {
    fn into_source(self, report: &mut Report) -> *mut ffi::mu_Source {
        use std::ffi::c_uint;

        #[repr(C)]
        struct UdSource<'a, S> {
            base: ffi::mu_Source,
            src: Option<Box<S>>,
            report: *mut Report<'a>,
            line: ffi::mu_Line,
        }

        extern "C" fn init_fn<S: Source>(src: *mut ffi::mu_Source) -> c_int {
            // SAFETY: src is a valid UdSource<S> pointer created in into_source below
            let ud = unsafe { &mut (*(src as *mut UdSource<S>)) };
            // SAFETY: Same pointer, different reference for clarity
            let udsrc = unsafe { &mut *(ud as *mut UdSource<S>) };
            match udsrc.src.as_mut().unwrap().init() {
                Ok(_) => 0,
                Err(err) => {
                    // SAFETY: report pointer is valid for the lifetime of the source
                    unsafe { &mut *udsrc.report }.src_err = Some(err);
                    ffi::MU_ERRFILE
                }
            }
        }

        extern "C" fn free_fn<S: Source>(src: *mut ffi::mu_Source) {
            // SAFETY: src is a valid UdSource<S> pointer, called only once by C library
            let ud = unsafe { &mut *(src as *mut UdSource<S>) };
            let _src = ud.src.take();
            // Box<S> will be dropped automatically
        }

        extern "C" fn get_line_fn<S: Source>(
            src: *mut ffi::mu_Source,
            line_no: c_uint,
        ) -> ffi::mu_Slice {
            // SAFETY: src is a valid UdSource<S> pointer
            let ud = unsafe { &mut *(src as *mut UdSource<S>) };
            // SAFETY: Same pointer cast for immutable access
            let udsrc = unsafe { &*(ud as *mut UdSource<S>) };
            udsrc
                .src
                .as_ref()
                .unwrap()
                .get_line(line_no as usize)
                .into()
        }

        extern "C" fn get_line_info_fn<S: Source>(
            src: *mut ffi::mu_Source,
            line_no: c_uint,
        ) -> *const ffi::mu_Line {
            // SAFETY: src is a valid UdSource<S> pointer
            let ud = unsafe { &mut *(src as *mut UdSource<S>) };
            // SAFETY: Need mutable access to update ud.line
            let udsrc = unsafe { &mut *(ud as *mut UdSource<S>) };
            let line_info = udsrc.src.as_ref().unwrap().get_line_info(line_no as usize);
            udsrc.line = line_info.into();
            &udsrc.line
        }

        extern "C" fn line_for_chars_fn<S: Source>(
            src: *mut ffi::mu_Source,
            char_pos: usize,
            out_line: *mut *const ffi::mu_Line,
        ) -> c_uint {
            // SAFETY: src is a valid UdSource<S> pointer
            let ud = unsafe { &mut *(src as *mut UdSource<S>) };
            // SAFETY: Need immutable access to call line_for_chars
            let udsrc = unsafe { &*(ud as *mut UdSource<S>) };
            let (line_no, line_info) = udsrc.src.as_ref().unwrap().line_for_chars(char_pos);
            if !out_line.is_null() {
                ud.line = line_info.into();
                // SAFETY: out_line is checked
                unsafe { *out_line = &ud.line };
            }
            line_no as c_uint
        }

        extern "C" fn line_for_bytes_fn<S: Source>(
            src: *mut ffi::mu_Source,
            byte_pos: usize,
            out_line: *mut *const ffi::mu_Line,
        ) -> c_uint {
            // SAFETY: src is a valid UdSource<S> pointer
            let ud = unsafe { &mut *(src as *mut UdSource<S>) };
            // SAFETY: Need immutable access to call line_for_bytes
            let udsrc = unsafe { &*(ud as *mut UdSource<S>) };
            let (line_no, line_info) = udsrc.src.as_ref().unwrap().line_for_bytes(byte_pos);
            if !out_line.is_null() {
                ud.line = line_info.into();
                // SAFETY: out_line is checked
                unsafe { *out_line = &ud.line };
            }
            line_no as c_uint
        }

        // SAFETY: Creating a custom source with proper C callbacks.
        // The UdSource<S> layout matches mu_Source expectations,
        // and all function pointers have matching signatures.
        unsafe {
            let size = std::mem::size_of::<UdSource<S>>();
            let src = ffi::mu_newsource(report.ptr, size, self.name);
            (*src).line_no_offset = self.line_no_offset;
            {
                let udsrc = src as *mut UdSource<S>;
                (*udsrc).src = Some(Box::new(self.src));
            }
            (*src).init = Some(init_fn::<S>);
            (*src).free = Some(free_fn::<S>);
            (*src).get_line = Some(get_line_fn::<S>);
            (*src).get_line_info = Some(get_line_info_fn::<S>);
            (*src).line_for_chars = Some(line_for_chars_fn::<S>);
            (*src).line_for_bytes = Some(line_for_bytes_fn::<S>);
            src
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
///     .with_label((0..3, 0)) // label in source 0
///     .with_message("here")
///     .with_label((3..6, 1)) // label in source 1
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
    color_buf: [u8; ffi::MU_COLOR_CODE_SIZE],
    /// Box is necessary to ensure pointer stability when Vec grows
    #[allow(clippy::vec_box)]
    color_uds: Vec<Box<ColorUd>>,
    src_err: Option<io::Error>,
    _marker: PhantomData<&'a str>,
}

impl<'a> Report<'a> {
    /// Create a new report.
    pub fn new() -> Self {
        // SAFETY: mu_new allocates a new report, returns null on failure (checked below)
        let ptr = unsafe { ffi::mu_new(None, ptr::null_mut()) };
        assert!(!ptr.is_null(), "Failed to allocate report");
        Self {
            ptr,
            config: None,
            color_buf: [0; ffi::MU_COLOR_CODE_SIZE],
            color_uds: Vec::new(),
            src_err: None,
            _marker: PhantomData,
        }
    }

    /// Configure the report.
    #[must_use]
    pub fn with_config(mut self, config: Config<'a>) -> Self {
        self.config = Some(config);
        self
    }

    /// Reset the report for reuse.
    pub fn reset(self) -> Self {
        // SAFETY: self.ptr is a valid mu_Report pointer owned by this Report
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
    ///     .with_source(("code", "file.rs"))  // ID 0
    ///     .with_source(("x", "other.rs"));   // ID 1
    /// ```
    #[must_use]
    pub fn with_source<S: IntoSource>(mut self, source: S) -> Self {
        let src_ptr = source.into_source(&mut self);
        // SAFETY: self.ptr and src_ptr are both valid pointers
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
    #[must_use]
    pub fn with_title<L: Into<TitleLevel<'a>>>(self, level: L, message: &'a str) -> Self {
        let tl = level.into();
        // SAFETY: self.ptr is valid, message lifetime is bound to 'a
        unsafe { ffi::mu_title(self.ptr, tl.level, tl.custom_name, message.into()) };
        self
    }

    /// Set the error code.
    #[must_use]
    pub fn with_code(self, code: &'a str) -> Self {
        // SAFETY: self.ptr is valid, code lifetime is bound to 'a
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
    ///     .with_label((0..3, 0))  // label in source 0
    ///     .with_message("here");
    /// ```
    #[must_use]
    pub fn with_label<L: Into<LabelSpan>>(self, span: L) -> Self {
        let span = span.into();
        // SAFETY: self.ptr is valid, span values are checked by C library
        unsafe { ffi::mu_label(self.ptr, span.start, span.end, span.src_id) };
        self
    }

    /// Set the message for the last added label.
    #[must_use]
    pub fn with_message(self, msg: &'a str) -> Self {
        let width = unicode_width(msg);
        // SAFETY: self.ptr is valid, msg lifetime is bound to 'a
        unsafe { ffi::mu_message(self.ptr, msg.into(), width) };
        self
    }

    /// Set the color for the last added label.
    ///
    /// This method accepts anything that implements [`IntoColor`], including:
    /// - `&dyn Color` - Custom color trait objects
    /// - `&GenColor` - Pre-generated colors from [`ColorGenerator`]
    ///
    /// # Examples
    ///
    /// Using a custom color:
    /// ```rust
    /// # use musubi::{Report, Level, Color, ColorKind};
    /// # use std::io::Write;
    /// struct MyColor;
    /// impl Color for MyColor {
    ///     fn color(&self, w: &mut dyn Write, kind: ColorKind) -> std::io::Result<()> {
    ///         write!(w, "\x1b[31m") // Red
    ///     }
    /// }
    ///
    /// let color = MyColor;
    /// let mut report = Report::new()
    ///     .with_source(("code", "test.rs"))
    ///     .with_label(0..4)
    ///     .with_color(&color);
    /// ```
    ///
    /// Using a color generator:
    /// ```rust
    /// # use musubi::{Report, Level, ColorGenerator};
    /// let mut cg = ColorGenerator::new();
    /// let mut report = Report::new()
    ///     .with_source(("code", "test.rs"))
    ///     .with_label(0..4)
    ///     .with_color(&cg.next_color());
    /// ```
    #[must_use]
    pub fn with_color<C: IntoColor>(mut self, color: C) -> Self {
        color.into_color(&mut self);
        self
    }

    /// Set the display order for the last added label.
    ///
    /// Labels with lower order values are displayed first (closer to the code).
    /// Labels with the same order are displayed in the order they were added.
    ///
    /// Default: `0`
    ///
    /// # Example
    /// ```rust
    /// # use musubi::{Report, Level};
    /// let mut report = Report::new()
    ///     .with_source(("code", "test.rs"))
    ///     .with_title(Level::Error, "Error")
    ///     .with_label(0..4)
    ///     .with_message("first")
    ///     .with_order(-1)  // Display this label first
    ///     .with_label(0..4)
    ///     .with_message("second")
    ///     .with_order(1);  // Display this label second
    /// ```
    #[must_use]
    pub fn with_order(self, order: i32) -> Self {
        // SAFETY: self.ptr is valid
        unsafe { ffi::mu_order(self.ptr, order) };
        self
    }

    /// Set the priority for the last added label.
    ///
    /// Priority affects label clustering: labels with higher priority
    /// are less likely to be grouped together with other labels.
    ///
    /// Higher values = higher priority = less clustering.
    ///
    /// Default: `0`
    ///
    /// # Example
    /// ```rust
    /// # use musubi::{Report, Level};
    /// let mut report = Report::new()
    ///     .with_source(("code here", "test.rs"))
    ///     .with_title(Level::Error, "Error")
    ///     .with_label(0..4)
    ///     .with_message("primary error")
    ///     .with_priority(10)  // High priority, won't cluster
    ///     .with_label(5..9)
    ///     .with_message("related note")
    ///     .with_priority(0);  // Low priority, may cluster
    /// ```
    #[must_use]
    pub fn with_priority(self, priority: i32) -> Self {
        // SAFETY: self.ptr is valid
        unsafe { ffi::mu_priority(self.ptr, priority) };
        self
    }

    /// Add a help message to the diagnostic.
    ///
    /// Help messages appear at the end of the diagnostic,
    /// providing suggestions or additional context.
    ///
    /// Multiple help messages can be added and will be displayed in order.
    ///
    /// # Example
    /// ```rust
    /// # use musubi::{Report, Level};
    /// let mut report = Report::new()
    ///     .with_source(("code", "test.rs"))
    ///     .with_title(Level::Error, "Type error")
    ///     .with_label(0..4)
    ///     .with_message("expected String")
    ///     .with_help("try converting with .to_string()");
    /// ```
    #[must_use]
    pub fn with_help(self, msg: &'a str) -> Self {
        // SAFETY: self.ptr is valid, msg lifetime is bound to 'a
        unsafe { ffi::mu_help(self.ptr, msg.into()) };
        self
    }

    /// Add a note message to the diagnostic.
    ///
    /// Notes appear at the end of the diagnostic,
    /// providing additional information or context.
    ///
    /// Multiple notes can be added and will be displayed in order.
    ///
    /// # Example
    /// ```rust
    /// # use musubi::{Report, Level};
    /// let mut report = Report::new()
    ///     .with_source(("code", "test.rs"))
    ///     .with_title(Level::Warning, "Unused variable")
    ///     .with_label(0..4)
    ///     .with_message("never used")
    ///     .with_note("consider prefixing with an underscore: `_code`");
    /// ```
    #[must_use]
    pub fn with_note(self, msg: &'a str) -> Self {
        // SAFETY: self.ptr is valid, msg lifetime is bound to 'a
        unsafe { ffi::mu_note(self.ptr, msg.into()) };
        self
    }

    /// Render the report to a String.
    ///
    /// - `pos`: The byte position in the source for header location display
    /// - `src_id`: The primary source ID (registration order)
    pub fn render_to_string(&mut self, pos: usize, src_id: usize) -> io::Result<String> {
        let mut writer = Vec::new();
        unsafe extern "C" fn string_writer_callback(
            ud: *mut c_void,
            data: *const c_char,
            len: usize,
        ) -> c_int {
            // SAFETY: ud is a valid &mut Vec<u8> pointer passed to mu_writer below
            let writer = unsafe { &mut *(ud as *mut Vec<u8>) };
            // SAFETY: data and len are provided by C library, guaranteed to be valid
            let slice = unsafe { std::slice::from_raw_parts(data as *const u8, len) };
            writer.extend_from_slice(slice);
            ffi::MU_OK
        }
        // SAFETY: self.ptr is valid, callback has correct signature, writer is valid for this scope
        unsafe {
            ffi::mu_writer(
                self.ptr,
                Some(string_writer_callback),
                &mut writer as *mut Vec<u8> as *mut c_void,
            )
        };
        self.render(pos, src_id).map(|_| {
            String::from_utf8(writer)
                .unwrap_or_else(|e| String::from_utf8_lossy(&e.into_bytes()).into_owned())
        })
    }

    /// Render the report to stdout.
    pub fn render_to_stdout(&mut self, pos: usize, src_id: usize) -> io::Result<()> {
        unsafe extern "C" fn stdout_writer_callback(
            _ud: *mut c_void,
            data: *const c_char,
            len: usize,
        ) -> c_int {
            // SAFETY: data and len are provided by C library, guaranteed to be valid
            let slice = unsafe { std::slice::from_raw_parts(data as *const u8, len) };
            let mut stdout = io::stdout();
            if stdout.write_all(slice).is_ok() && stdout.flush().is_ok() {
                ffi::MU_OK
            } else {
                ffi::MU_ERRPARAM
            }
        }

        // SAFETY: self.ptr is valid, callback has correct signature
        unsafe { ffi::mu_writer(self.ptr, Some(stdout_writer_callback), ptr::null_mut()) };
        self.render(pos, src_id)
    }

    /// Render the report to a writer.
    pub fn render_to_writer<'b, W: Write>(
        &'b mut self,
        pos: usize,
        src_id: usize,
        writer: &'b mut W,
    ) -> io::Result<()> {
        struct WriterWrapper<'a, W: Write> {
            writer: &'a mut W,
            report: *mut Report<'a>,
        }

        unsafe extern "C" fn writer_callback<W: Write>(
            ud: *mut c_void,
            data: *const c_char,
            len: usize,
        ) -> c_int {
            // SAFETY: ud is a valid WriterWrapper<W> pointer passed to mu_writer below
            let w = unsafe { &mut *(ud as *mut WriterWrapper<W>) };
            // SAFETY: data and len are provided by C library, guaranteed to be valid
            let slice = unsafe { std::slice::from_raw_parts(data as *const u8, len) };
            match w.writer.write_all(slice) {
                Ok(_) => ffi::MU_OK,
                Err(e) => {
                    // SAFETY: report pointer is setted below, and this function only called during render()
                    unsafe { &mut *w.report }.src_err = Some(e);
                    ffi::MU_ERR_WRITER
                }
            }
        }
        #[allow(clippy::unnecessary_cast)]
        let mut wrapper = WriterWrapper {
            writer,
            report: self as *mut Report<'a> as *mut Report<'b>,
        };
        // SAFETY: mu_writer expects a valid Report pointer and writer callback
        unsafe {
            ffi::mu_writer(
                self.ptr,
                Some(writer_callback::<W>),
                &mut wrapper as *mut WriterWrapper<W> as *mut c_void,
            );
        }
        self.render(pos, src_id)
    }

    fn render(&mut self, pos: usize, src_id: impl Into<ffi::mu_Id>) -> io::Result<()> {
        let mut buf = [0u8; ffi::MU_COLOR_CODE_SIZE];
        let cs_buf: CharSetBuf;
        let cs: ffi::mu_Charset;
        if let Some(config) = &mut self.config
            && let Some(char_set) = config.char_set
        {
            cs_buf = (*char_set).into();
            cs = cs_buf.into();
            config.inner.char_set = &cs as *const ffi::mu_Charset;
        }
        if let Some(cfg) = self.config.as_mut()
            && let Some(color_ud) = cfg.color_ud.as_mut()
        {
            color_ud.color_buf = &mut buf as *mut [u8; ffi::MU_COLOR_CODE_SIZE];
        }
        for color_ud in &mut self.color_uds {
            color_ud.color_buf = &mut buf as *mut [u8; ffi::MU_COLOR_CODE_SIZE];
        }
        if let Some(cfg) = &self.config {
            // SAFETY: self.ptr is valid, cfg.inner is a valid config with lifetime guarantees
            unsafe { ffi::mu_config(self.ptr, &cfg.inner) };
        }
        // SAFETY: self.ptr is valid, all sources and labels have been properly registered
        match unsafe { ffi::mu_render(self.ptr, pos, src_id.into()) } {
            ffi::MU_OK => Ok(()),
            ffi::MU_ERR_SRCINIT => {
                if let Some(err) = self.src_err.take() {
                    return Err(err);
                }
                Err(io::Error::other("Source init error during rendering"))
            }
            ffi::MU_ERR_WRITER => {
                if let Some(err) = self.src_err.take() {
                    return Err(err);
                }
                Err(io::Error::other("Writer error during rendering"))
            }
            err_code => Err(io::Error::other(format!(
                "Rendering failed with error code {}",
                err_code
            ))),
        }
    }
}

/// Internal buffer for character set conversion to C representation.
///
/// Converts Rust [`CharSet`] into a C-compatible array of chunk pointers.
/// Each character is encoded as: `[length_byte, utf8_byte1, utf8_byte2, ...]`
///
/// The buffer contains 23 entries (one for each CharSet field), each up to
/// 8 bytes (1 length byte + up to 7 UTF-8 bytes, though most characters are 1-3 bytes).
struct CharSetBuf {
    /// 23 characters × 8 bytes each (length prefix + UTF-8 data)
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
            if c == '.' {
                return [3, b'.', b'.', b'.', 0, 0, 0, 0];
            }
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
        // SAFETY: self.ptr is a valid mu_Report pointer owned by this Report
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
            .with_label(0..3)
            .with_message("this is a test");

        let output = report.render_to_string(0, 0).unwrap();
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
            .with_label(0..5)
            .with_message("test");

        let output = report.render_to_string(0, 0).unwrap();
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Warning: Test warning
               ,-[ test.rs:1:1 ]
             1 |hello
               |^^|^^
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
            .with_label(0..4)
            .with_message("here");

        let output = report.render_to_string(0, 0).unwrap();
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
            .with_label((7..10, 0))
            .with_message("imported here")
            .with_label((7..10, 1))
            .with_message("defined here");

        let output = report.render_to_string(7, 0).unwrap();
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
            .with_source(("test code", "file.rs"))
            .with_title(Level::Error, "Error")
            .with_label((0..4, 0))
            .with_message("here");

        let output = report.render_to_string(0, 0).unwrap();
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

        let output = report.render_to_string(0, 0).unwrap();
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

        let output = report.render_to_string(0, 0).unwrap();
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

        let output = report.render_to_string(0, 0).unwrap();
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
    fn test_color_gen() {
        let mut cg = ColorGenerator::new();
        let label1 = cg.next_color();

        let mut report = Report::new()
            .with_config(Config::new().with_char_set_ascii())
            .with_source(("klmnop", "<unknown>"))
            .with_title(Level::Error, "test colors")
            .with_label(0..6usize)
            .with_message("here")
            .with_color(&label1);

        let output = report.render_to_string(0, 0).unwrap();
        assert_snapshot!(
            remove_trailing_whitespace(&output).replace('\x1b', "ESC"),
            @r##"
            ESC[31mError:ESC[0m test colors
               ESC[38;5;246m,-[ESC[0m <unknown>:1:1 ESC[38;5;246m]ESC[0m
               ESC[38;5;246m|ESC[0m
             ESC[38;5;246m1 |ESC[0m ESC[38;5;201mklmnopESC[0m
               ESC[38;5;240m|ESC[0m ESC[38;5;201m^^^|^^ESC[0m
               ESC[38;5;240m|ESC[0m    ESC[38;5;201m`----ESC[0m here
            ESC[38;5;246m---'ESC[0m
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

        let output = report.render_to_string(0, 0).unwrap();
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
                ("some code here", "file.rs", 99), // Line numbers start at 100
            )
            .with_title(Level::Error, "Error")
            .with_label(0..4usize)
            .with_message("here");

        let output = report.render_to_string(0, 0).unwrap();
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

    #[test]
    fn custom_source() {
        struct MySource;

        impl Source for MySource {
            fn init(&mut self) -> io::Result<()> {
                Ok(())
            }

            fn get_line(&self, _line_no: usize) -> &[u8] {
                b"some code here"
            }

            fn get_line_info(&self, line_no: usize) -> Line {
                Line {
                    offset: 15 * line_no,
                    byte_offset: 15 * line_no,
                    len: 14,
                    byte_len: 14,
                    newline: 1,
                }
            }

            fn line_for_bytes(&self, byte_pos: usize) -> (usize, Line) {
                let line_no = byte_pos / 15;
                (
                    line_no,
                    Line {
                        offset: 15 * line_no,
                        byte_offset: 15 * line_no,
                        len: 14,
                        byte_len: 14,
                        newline: 1,
                    },
                )
            }

            fn line_for_chars(&self, char_pos: usize) -> (usize, Line) {
                let line_no = char_pos / 15;
                (
                    line_no,
                    Line {
                        offset: 15 * line_no,
                        byte_offset: 15 * line_no,
                        len: 14,
                        byte_len: 14,
                        newline: 1,
                    },
                )
            }
        }

        let mut report = Report::new()
            .with_config(Config::new().with_color_disabled())
            .with_source((MySource, "file.rs"))
            .with_title(Level::Error, "Error")
            .with_label(1485..1489usize)
            .with_message("here");

        let output = report.render_to_string(1485, 0).unwrap();
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

    #[test]
    fn test_config_options() {
        // Test various config options
        let config = Config::new()
            .with_cross_gap(false)
            .with_compact(false)
            .with_underlines(true)
            .with_multiline_arrows(true)
            .with_tab_width(2)
            .with_limit_width(40)
            .with_ambi_width(2)
            .with_label_attach(LabelAttach::Start)
            .with_index_type(IndexType::Char)
            .with_char_set_ascii()
            .with_color_disabled();

        let mut report = Report::new()
            .with_config(config)
            .with_source(("hello\tworld", "test.rs"))
            .with_title(Level::Error, "Test")
            .with_label(0..5)
            .with_message("here");

        let output = report.render_to_string(0, 0).unwrap();
        assert!(output.contains("hello"));
    }

    #[test]
    fn test_index_type_byte() {
        let config = Config::new()
            .with_index_type(IndexType::Byte)
            .with_char_set_ascii()
            .with_color_disabled();

        let mut report = Report::new()
            .with_config(config)
            .with_source(("hello", "test.rs"))
            .with_title(Level::Error, "Test")
            .with_label(0..5)
            .with_message("bytes");

        let output = report.render_to_string(0, 0).unwrap();
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Error: Test
               ,-[ test.rs:1:1 ]
               |
             1 | hello
               | ^^|^^
               |   `---- bytes
            ---'
            "##
        );
    }

    #[test]
    fn test_label_attach_start() {
        let config = Config::new()
            .with_label_attach(LabelAttach::Start)
            .with_char_set_ascii()
            .with_color_disabled();

        let mut report = Report::new()
            .with_config(config)
            .with_source(("hello world", "test.rs"))
            .with_title(Level::Error, "Test")
            .with_label(0..5)
            .with_message("start");

        let output = report.render_to_string(0, 0).unwrap();
        assert!(output.contains("start"));
    }

    #[test]
    fn test_label_attach_end() {
        let config = Config::new()
            .with_label_attach(LabelAttach::End)
            .with_char_set_ascii()
            .with_color_disabled();

        let mut report = Report::new()
            .with_config(config)
            .with_source(("hello world", "test.rs"))
            .with_title(Level::Error, "Test")
            .with_label(0..5)
            .with_message("end");

        let output = report.render_to_string(0, 0).unwrap();
        assert!(output.contains("end"));
    }

    #[test]
    fn test_with_order() {
        let mut report = Report::new()
            .with_config(Config::new().with_char_set_ascii().with_color_disabled())
            .with_source(("code here", "test.rs"))
            .with_title(Level::Error, "Test")
            .with_label(0..4)
            .with_message("second")
            .with_order(1)
            .with_label(0..4)
            .with_message("first")
            .with_order(-1);

        let output = report.render_to_string(0, 0).unwrap();
        // Verify both labels appear
        assert!(output.contains("first"));
        assert!(output.contains("second"));
    }

    #[test]
    fn test_with_priority() {
        let mut report = Report::new()
            .with_config(Config::new().with_char_set_ascii().with_color_disabled())
            .with_source(("code here", "test.rs"))
            .with_title(Level::Error, "Test")
            .with_label(0..4)
            .with_message("high priority")
            .with_priority(10)
            .with_label(5..9)
            .with_message("low priority")
            .with_priority(0);

        let output = report.render_to_string(0, 0).unwrap();
        assert!(output.contains("high priority"));
        assert!(output.contains("low priority"));
    }

    #[test]
    fn test_with_help() {
        let mut report = Report::new()
            .with_config(Config::new().with_char_set_ascii().with_color_disabled())
            .with_source(("code", "test.rs"))
            .with_title(Level::Error, "Type error")
            .with_label(0..4)
            .with_message("wrong type")
            .with_help("try using .to_string()");

        let output = report.render_to_string(0, 0).unwrap();
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Error: Type error
               ,-[ test.rs:1:1 ]
               |
             1 | code
               | ^^|^
               |   `--- wrong type
               |
               | Help: try using .to_string()
            ---'
            "##
        );
    }

    #[test]
    fn test_with_note() {
        let mut report = Report::new()
            .with_config(Config::new().with_char_set_ascii().with_color_disabled())
            .with_source(("code", "test.rs"))
            .with_title(Level::Warning, "Unused variable")
            .with_label(0..4)
            .with_message("never used")
            .with_note("consider prefixing with `_`");

        let output = report.render_to_string(0, 0).unwrap();
        assert_snapshot!(
            remove_trailing_whitespace(&output),
            @r##"
            Warning: Unused variable
               ,-[ test.rs:1:1 ]
               |
             1 | code
               | ^^|^
               |   `--- never used
               |
               | Note: consider prefixing with `_`
            ---'
            "##
        );
    }

    #[test]
    fn test_multiple_help_and_notes() {
        let mut report = Report::new()
            .with_config(Config::new().with_char_set_ascii().with_color_disabled())
            .with_source(("code", "test.rs"))
            .with_title(Level::Error, "Error")
            .with_label(0..4)
            .with_message("problem")
            .with_help("first help")
            .with_help("second help")
            .with_note("first note")
            .with_note("second note");

        let output = report.render_to_string(0, 0).unwrap();
        assert!(output.contains("first help"));
        assert!(output.contains("second help"));
        assert!(output.contains("first note"));
        assert!(output.contains("second note"));
    }

    #[test]
    fn test_empty_source() {
        let mut report = Report::new()
            .with_config(Config::new().with_char_set_ascii().with_color_disabled())
            .with_source(("", "empty.rs"))
            .with_title(Level::Error, "Empty file")
            .with_label(0..0)
            .with_message("empty");

        // Should not panic
        let output = report.render_to_string(0, 0).unwrap();
        assert!(output.contains("empty.rs"));
    }

    #[test]
    fn test_render_to_stdout() {
        let mut report = Report::new()
            .with_config(Config::new().with_char_set_ascii().with_color_disabled())
            .with_source(("code", "test.rs"))
            .with_title(Level::Error, "Test")
            .with_label(0..4)
            .with_message("test");

        // Should not panic (output goes to stdout)
        let result = report.render_to_stdout(0, 0);
        assert!(result.is_ok());
    }

    #[test]
    fn test_render_to_writer() {
        let mut report = Report::new()
            .with_config(Config::new().with_char_set_ascii().with_color_disabled())
            .with_source(("code", "test.rs"))
            .with_title(Level::Error, "Test")
            .with_label(0..4)
            .with_message("test");

        let mut buffer = Vec::new();
        {
            let buf = &mut buffer;
            let result = report.render_to_writer(0, 0, buf);
            assert!(result.is_ok());
            assert!(!buffer.is_empty());
        }

        let output = String::from_utf8(buffer).unwrap();
        assert!(output.contains("Error"));
        assert!(output.contains("test"));
    }

    #[test]
    fn test_reset() {
        let report = Report::new()
            .with_config(Config::new().with_char_set_ascii().with_color_disabled())
            .with_source(("code", "test.rs"))
            .with_title(Level::Error, "Test")
            .with_label(0..4)
            .with_message("test");

        // Reset and reuse
        let mut report = report
            .reset()
            .with_source(("new code", "new.rs"))
            .with_title(Level::Warning, "New")
            .with_label(0..3)
            .with_message("new");

        let output = report.render_to_string(0, 0).unwrap();
        assert!(output.contains("Warning"));
        assert!(output.contains("new"));
    }

    #[test]
    fn test_char_set_conversion() {
        let ascii = CharSet::ascii();
        let unicode = CharSet::unicode();

        // ASCII should use simple characters
        assert_eq!(ascii.hbar, '-');
        assert_eq!(ascii.vbar, '|');

        // Unicode should use box-drawing characters
        assert_ne!(unicode.hbar, '-');
        assert_ne!(unicode.vbar, '|');
    }
}
