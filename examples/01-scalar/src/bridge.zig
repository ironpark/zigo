//! The C++ side of the example, as its own Zig module. The static library and
//! the bridge source hang off this module rather than off `scalar`, which is
//! what a binding sees when it imports a library that links its own C++
//! dependencies: the link inputs live on an imported module, and zigo has to
//! reach them there.
pub extern fn scalar_bridge_add(a: i32, b: i32) callconv(.c) i32;
