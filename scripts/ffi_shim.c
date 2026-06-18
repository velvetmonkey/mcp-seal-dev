/* SPDX-License-Identifier: Apache-2.0
 * Visibility shim linked into libsealv2ffi.so: re-exports the Ffi module
 * initializer and the static-inline lean.h helpers the Rust host needs
 * (Rust cannot call static inlines directly).
 */
#include <lean/lean.h>

/* Module initializer for `Ffi` in package `mcp-seal` (the `-` mangles to `x2d`).
 * Lean v4.28.0 initializers take only (uint8_t builtin) and return the IO result
 * directly. The public wrapper keeps the (builtin, world) shape for caller ABI
 * compatibility; the world token is unused. */
extern lean_object* initialize_mcp_x2dseal_Ffi(uint8_t builtin);

LEAN_EXPORT lean_object* seal_v2_ffi_initialize(uint8_t builtin, lean_object* w) {
    (void)w;
    return initialize_mcp_x2dseal_Ffi(builtin);
}

LEAN_EXPORT char const* seal_lean_string_cstr(b_lean_obj_arg o) {
    return lean_string_cstr(o);
}

LEAN_EXPORT uint8_t seal_lean_io_result_is_ok(b_lean_obj_arg r) {
    return lean_io_result_is_ok(r);
}

LEAN_EXPORT void seal_lean_dec(lean_obj_arg o) {
    lean_dec(o);
}

LEAN_EXPORT lean_object* seal_lean_mk_string(char const* s, size_t n) {
    return lean_mk_string_from_bytes(s, n);
}
