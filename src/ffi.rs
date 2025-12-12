#![allow(non_camel_case_types)]
#![allow(dead_code)]

include!("ffi_generated.rs");

pub mod sizes {
    pub const COLOR_CODE: usize = super::MU_COLOR_CODE_SIZE as usize;
}

pub const MU_OK: i32 = 0;
pub const MU_ERR_WRITER: i32 = -99;
pub const MU_ERR_SRCINIT: i32 = -100;

#[repr(transparent)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct mu_Id(std::os::raw::c_uint);

macro_rules! impl_from_for_mu_id {
    ($($t:ty),+) => {
        $(
            impl From<$t> for mu_Id {
                fn from(value: $t) -> Self {
                    mu_Id(value as std::os::raw::c_uint)
                }
            }
        )+
    };
}
impl_from_for_mu_id!(i32, u32, usize);

impl Default for mu_Slice {
    fn default() -> Self {
        mu_Slice {
            p: std::ptr::null(),
            e: std::ptr::null(),
        }
    }
}

impl From<&[u8]> for mu_Slice {
    fn from(slice: &[u8]) -> Self {
        mu_Slice {
            p: slice.as_ptr() as *const i8,
            // SAFETY: slice is valid, so adding len is safe
            e: unsafe { slice.as_ptr().add(slice.len()) as *const i8 },
        }
    }
}

impl From<mu_Slice> for &[u8] {
    fn from(slice: mu_Slice) -> Self {
        // SAFETY: slice.p and slice.e are from a valid slice
        let len = unsafe { slice.e.offset_from(slice.p) as usize };
        // SAFETY: slice.p is valid for len bytes
        unsafe { std::slice::from_raw_parts(slice.p as *const u8, len) }
    }
}

impl From<&str> for mu_Slice {
    fn from(s: &str) -> Self {
        mu_Slice {
            p: s.as_ptr() as *const i8,
            // SAFETY: s is valid, so adding len is safe
            e: unsafe { s.as_ptr().add(s.len()) as *const i8 },
        }
    }
}

impl From<mu_Slice> for Result<&str, std::str::Utf8Error> {
    fn from(slice: mu_Slice) -> Self {
        // SAFETY: slice.p and slice.e are from a valid slice
        let len = unsafe { slice.e.offset_from(slice.p) as usize };
        // SAFETY: slice.p is valid for len bytes
        let bytes = unsafe { std::slice::from_raw_parts(slice.p as *const u8, len) };
        std::str::from_utf8(bytes)
    }
}
