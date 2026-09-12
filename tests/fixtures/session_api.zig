//! A minimal bound library for the session reflection test: one primary handle
//! that hands out a dependent child, and nothing else.
pub const Queue = struct {
    pub fn create() error{OutOfMemory}!*Queue {
        return error.OutOfMemory;
    }
    pub fn deinit(_: *Queue) void {}
    pub fn newStream(_: *Queue) error{OutOfMemory}!*Stream {
        return error.OutOfMemory;
    }
};

pub const Stream = struct {
    pub fn free(_: *Stream) void {}
};
