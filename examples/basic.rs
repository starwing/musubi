//! Basic example demonstrating musubi usage
//!
//! Run with: cargo run --example basic

use musubi::{CharSet, Config, Level, Report};

fn main() {
    // Example 1: Simple error report
    println!("=== Example 1: Simple Error ===\n");
    {
        let code = r#"fn main() {
    let x = "hello;
}"#;

        let mut report = Report::new()
            .with_source((code, "main.rs"))
            .with_title(Level::Error, "Unterminated string literal")
            .with_code("E0001")
            .with_label(24..30)
            .with_message("missing closing quote");

        println!("{}", report.render_to_string(20, 0).unwrap());
    }

    // Example 2: Multiple labels
    println!("=== Example 2: Multiple Labels ===\n");
    {
        let code = "let x: i32 = \"hello\";";

        let mut report = Report::new()
            .with_source((code, "types.rs"))
            .with_title(Level::Error, "Type mismatch")
            .with_code("E0308")
            .with_label(7..10)
            .with_message("expected type")
            .with_label(13..20)
            .with_message("found `&str`");

        println!("{}", report.render_to_string(7, 0).unwrap());
    }

    // Example 3: Custom configuration with builder pattern
    println!("=== Example 3: Custom Configuration (Compact) ===\n");
    {
        let char_set = CharSet::ascii();
        let config = Config::new()
            .with_compact(true)
            .with_char_set(&char_set)
            .with_color_disabled()
            .with_underlines(false);

        let code = "fn foo(x: i32) { x + 1.0 }";

        let mut report = Report::new()
            .with_config(config)
            .with_source((code, "math.rs"))
            .with_title(Level::Error, "Cannot add `i32` and `f64`")
            .with_code("E0277")
            .with_label(17..24)
            .with_message("no implementation for `i32 + f64`")
            .with_help("Consider using `x as f64` or `1.0 as i32`");

        println!("{}", report.render_to_string(17, 0).unwrap());
    }

    // Example 4: Multiline spans
    println!("=== Example 4: Multiline Spans ===\n");
    {
        let code = r#"fn example() {
    if true {
        println!("hello");
    // missing closing brace
}
"#;

        let mut report = Report::new()
            .with_source((code, "braces.rs"))
            .with_title(Level::Error, "Mismatched braces")
            .with_code("E0065")
            .with_label(19..73)
            .with_message("this block is not properly closed")
            .with_note("Each opening brace `{` must have a matching closing brace `}`");

        println!("{}", report.render_to_string(19, 0).unwrap());
    }
}
