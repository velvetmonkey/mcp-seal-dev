// SPDX-License-Identifier: Apache-2.0
//! Minimal Lean 4 runtime FFI: initialise the runtime, exchange Lean strings,
//! and serialise all calls into the (non-thread-safe) Lean exports.
//!
//! TCB note (A3): everything here is trusted glue. A marshalling bug bypasses no
//! Lean proof — Lean still decides — but a routing bug would. Keep it tiny.
//!
//! A4: the `Mutex` makes every export call mutually exclusive. The Lean state is
//! a single `IO.Ref`; concurrent calls are UB and would also break M6's
//! atomic-consume (read→consume→write). The lock IS assumption A4.

use std::ffi::c_void;
use std::os::raw::c_char;
use std::sync::Mutex;

type LeanObj = *mut c_void;

#[allow(dead_code)] // echo/crypto_probe are bring-up self-test helpers
extern "C" {
    fn lean_initialize_runtime_module();
    fn lean_io_mark_end_initialization();
    fn lean_init_task_manager();
    // libsealv2ffi shim (scripts/ffi_shim.c)
    fn seal_v2_ffi_initialize(builtin: u8, world: LeanObj) -> LeanObj;
    fn seal_lean_io_result_is_ok(r: LeanObj) -> u8;
    fn seal_lean_dec(o: LeanObj);
    fn seal_lean_mk_string(s: *const c_char, n: usize) -> LeanObj;
    fn seal_lean_string_cstr(o: LeanObj) -> *const c_char;
    // libsealv2ffi @[export] surface
    fn seal_v2_init(config: LeanObj) -> LeanObj;
    fn seal_v2_add_approval(raw: LeanObj, sig: LeanObj) -> LeanObj;
    fn seal_v2_decide(req: LeanObj, now: LeanObj) -> LeanObj;
    fn seal_v2_echo(input: LeanObj) -> LeanObj;
    fn seal_v2_crypto_probe(pk: LeanObj, msg: LeanObj, sig: LeanObj) -> LeanObj;
}

unsafe fn lean_dec(o: LeanObj) {
    if !o.is_null() && (o as usize) & 1 == 0 {
        seal_lean_dec(o);
    }
}

fn to_lean_string(s: &str) -> LeanObj {
    unsafe { seal_lean_mk_string(s.as_ptr() as *const c_char, s.len()) }
}

/// The Lean IO "world" token: `lean_box(0)`.
fn lean_world() -> LeanObj {
    1usize as LeanObj
}

fn from_lean_string(o: LeanObj) -> String {
    unsafe {
        let p = seal_lean_string_cstr(o);
        std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned()
    }
}

/// Serialises all calls into the non-thread-safe Lean exports (A4).
pub struct LeanHost {
    lock: Mutex<()>,
}

impl LeanHost {
    /// Initialise the Lean runtime exactly once per process.
    pub fn new() -> Self {
        unsafe {
            lean_initialize_runtime_module();
            let res = seal_v2_ffi_initialize(1, lean_world());
            if seal_lean_io_result_is_ok(res) == 0 {
                panic!("Lean Ffi module initialisation failed");
            }
            lean_dec(res);
            lean_io_mark_end_initialization();
            lean_init_task_manager();
        }
        LeanHost { lock: Mutex::new(()) }
    }

    /// Initialise the session from a config JSON envelope.
    pub fn init(&self, config_json: &str) -> String {
        let _g = self.lock.lock().unwrap();
        unsafe {
            let r = seal_v2_init(to_lean_string(config_json));
            let out = from_lean_string(r);
            lean_dec(r);
            out
        }
    }

    /// Inject an approval token (canonical signed-message bytes + hex signature).
    pub fn add_approval(&self, raw_signed: &str, sig_hex: &str) -> String {
        let _g = self.lock.lock().unwrap();
        unsafe {
            let r = seal_v2_add_approval(to_lean_string(raw_signed), to_lean_string(sig_hex));
            let out = from_lean_string(r);
            lean_dec(r);
            out
        }
    }

    /// Mediate one raw request at clock `now`. Returns the decision JSON.
    pub fn decide(&self, raw_request: &str, now: &str) -> String {
        let _g = self.lock.lock().unwrap();
        unsafe {
            let r = seal_v2_decide(to_lean_string(raw_request), to_lean_string(now));
            let out = from_lean_string(r);
            lean_dec(r);
            out
        }
    }

    #[allow(dead_code)] // bring-up self-test helper
    pub fn echo(&self, s: &str) -> String {
        let _g = self.lock.lock().unwrap();
        unsafe {
            let r = seal_v2_echo(to_lean_string(s));
            let out = from_lean_string(r);
            lean_dec(r);
            out
        }
    }

    #[allow(dead_code)] // bring-up self-test helper
    pub fn crypto_probe(&self, pk_hex: &str, msg: &str, sig_hex: &str) -> String {
        let _g = self.lock.lock().unwrap();
        unsafe {
            let r = seal_v2_crypto_probe(
                to_lean_string(pk_hex),
                to_lean_string(msg),
                to_lean_string(sig_hex),
            );
            let out = from_lean_string(r);
            lean_dec(r);
            out
        }
    }
}
