// SPDX-License-Identifier: Apache-2.0
// Links the Lean verified-core FFI shared library (libsealv2ffi.so, built by
// scripts/build_ffi_so.sh) and the Lean runtime (libleanshared.so).
//   SEAL_FFI_LIB_DIR — directory containing libsealv2ffi.so
//   LEAN_LIB_DIR     — toolchain lib/lean directory
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let ffi_dir = std::env::var("SEAL_FFI_LIB_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| manifest.join("../.lake/build/lib"));
    let lean_dir = std::env::var("LEAN_LIB_DIR").map(PathBuf::from).unwrap_or_else(|_| {
        let out = Command::new("lean")
            .arg("--print-prefix")
            .output()
            .expect("lean --print-prefix (set LEAN_LIB_DIR to override)");
        PathBuf::from(String::from_utf8_lossy(&out.stdout).trim()).join("lib/lean")
    });
    for dir in [&ffi_dir, &lean_dir] {
        println!("cargo:rustc-link-search=native={}", dir.display());
        println!("cargo:rustc-link-arg=-Wl,-rpath,{}", dir.display());
    }
    println!("cargo:rustc-link-lib=dylib=sealv2ffi");
    println!("cargo:rustc-link-lib=dylib=leanshared");
    println!("cargo:rerun-if-env-changed=SEAL_FFI_LIB_DIR");
    println!("cargo:rerun-if-env-changed=LEAN_LIB_DIR");
}
