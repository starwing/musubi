use std::env;
use std::path::PathBuf;

fn main() {
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let src_path = PathBuf::from(&manifest_dir);

    // Compile musubi_impl.c which includes musubi.h with MU_IMPLEMENTATION
    cc::Build::new()
        .file(src_path.join("src/musubi_impl.c"))
        .include(src_path.parent().unwrap()) // Include parent dir for musubi.h
        .compile("musubi");

    // Tell cargo to rerun if these files change
    println!("cargo:rerun-if-changed=src/musubi_impl.c");
    println!("cargo:rerun-if-changed=musubi.h");
    println!("cargo:rerun-if-changed=unidata.h");
}
