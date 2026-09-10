//! Native stubs deliberately return tags Zig normally cannot produce. These
//! tests exercise the generated public boundary, not just conversion helpers.
use zigo_golden::*;

#[no_mangle]
extern "C" fn zg_echo(value: u8) -> u8 {
    value
}
#[no_mangle]
extern "C" fn zg_pick(value: i32) -> i32 {
    value
}
#[no_mangle]
extern "C" fn zg_echo_level(value: u8) -> u8 {
    value
}
#[no_mangle]
extern "C" fn zg_wire(value: u16) -> u16 {
    value
}
#[no_mangle]
extern "C" fn zg_get_tiny(value: u8) -> u8 {
    value
}
#[no_mangle]
extern "C" fn zg_invalid() -> u8 {
    255
}
#[no_mangle]
extern "C" fn zg_get_hidden() -> u8 {
    2
}
#[no_mangle]
unsafe extern "C" fn zg_fallible(value: i32, fail: u8, out: *mut i32) -> i32 {
    // An invalid payload on error must never be inspected by the wrapper.
    unsafe {
        *out = if fail != 0 { 99 } else { value };
    }
    i32::from(fail != 0)
}
#[no_mangle]
unsafe extern "C" fn zg_checked(value: u8, out: *mut u8) -> i32 {
    unsafe {
        *out = value;
    }
    if value == 7 {
        -256
    } else {
        0
    }
}
#[no_mangle]
extern "C" fn zg_caught_panic_message(_: i32) -> *const core::ffi::c_char {
    core::ptr::null()
}

#[test]
fn named_values_cross_both_directions() {
    assert_eq!(pick(Priority::Low), Priority::Low);
    assert_eq!(echo_level(Level::Info), Level::Info);
    assert_eq!(wire(WireId::Utf8Url), WireId::Utf8Url);
    assert_eq!(u16::from(WireId::HttpId), 1);
    assert_eq!(i32::from(Priority::Low), -1);
}

#[test]
fn every_open_byte_survives_the_native_boundary() {
    for tag in u8::MIN..=u8::MAX {
        let value = EraseDisplay::try_from(tag).unwrap();
        assert_eq!(u8::from(echo(value)), tag);
    }
    assert_eq!(echo(EraseDisplay::Above).to_string(), "above");
    assert_eq!(
        EraseDisplay::try_from(255).unwrap().to_string(),
        "EraseDisplay(255)"
    );
}

#[test]
fn invalid_closed_and_omitted_tags_are_checked() {
    assert_eq!(Level::try_from(255), Err(255));
    assert_eq!(Hidden::try_from(2), Err(2));
    assert!(std::panic::catch_unwind(invalid).is_err());
    assert!(std::panic::catch_unwind(get_hidden).is_err());
    assert_eq!(u8::from(OpenHidden::try_from(2).unwrap()), 2);
    assert_eq!(
        OpenHidden::try_from(2).unwrap().to_string(),
        "OpenHidden(2)"
    );
}

#[test]
fn status_is_checked_before_the_enum_payload() {
    assert_eq!(fallible(Priority::Low, false).unwrap(), Priority::Low);
    assert_eq!(
        fallible(Priority::Low, true).unwrap_err().kind,
        ErrorKind::Rejected
    );
    assert_eq!(checked(1), Level::Info);
    assert!(std::panic::catch_unwind(|| checked(2)).is_err());
    let failure = std::panic::catch_unwind(|| checked(7)).unwrap_err();
    assert!(failure
        .downcast_ref::<String>()
        .unwrap()
        .contains("native failure"));
}

#[test]
fn promoted_open_tags_stay_inside_the_zig_range() {
    for tag in 0..=7 {
        assert_eq!(u8::from(get_tiny(Tiny::try_from(tag).unwrap())), tag);
    }
    assert_eq!(Tiny::try_from(8), Err(8));
    assert_eq!(Tiny::try_from(255), Err(255));
    for tag in -4..=3 {
        assert_eq!(i8::from(TinySigned::try_from(tag).unwrap()), tag);
    }
    assert_eq!(TinySigned::try_from(-5), Err(-5));
    assert_eq!(TinySigned::try_from(4), Err(4));
}

#[test]
fn signed_and_wide_extremes_are_not_truncated() {
    assert_eq!(i8::from(SignedByte::Min), i8::MIN);
    assert_eq!(i16::from(SignedWord::Min), i16::MIN);
    assert_eq!(u32::from(Wide::Max), u32::MAX);
    assert_eq!(SignedWide::try_from(i64::MIN), Ok(SignedWide::Min));
    assert_eq!(SignedWide::try_from(i64::MAX), Ok(SignedWide::Max));
    assert_eq!(u64::from(UnsignedWide::Max), i64::MAX as u64);
}

#[test]
fn text_uses_only_live_zig_member_names() {
    assert_eq!("low".parse::<Priority>(), Ok(Priority::Low));
    assert_eq!(Priority::Low.to_string(), "low");
    assert_eq!("above".parse::<EraseDisplay>(), Ok(EraseDisplay::Above));
    assert!("Above".parse::<EraseDisplay>().is_err());
    assert!("EraseDisplay(99)".parse::<EraseDisplay>().is_err());
    assert!("secret".parse::<Hidden>().is_err());
    assert!("secret".parse::<OpenHidden>().is_err());
    assert_eq!(
        EmptyOpen::try_from(42).unwrap().to_string(),
        "EmptyOpen(42)"
    );
    assert!("anything".parse::<EmptyOpen>().is_err());
    assert_eq!("error".parse::<Words>(), Ok(Words::Error));
    assert_eq!("err".parse::<Words>(), Ok(Words::Err));
}
