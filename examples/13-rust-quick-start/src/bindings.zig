//! What the Rust backend covers, one declaration per shape.
const zigo = @import("zigo");
const library = @import("calculator");

const api = zigo.scope(library);
const tally = api.in("Tally");
const reading = api.in("Reading");

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        // A scalar, a borrowed slice, and an error union.
        api.func("add", .{}),
        api.func("sum", .{}),
        api.func("divide", .{}),
        // A handle Rust owns through `Drop`. `create` and `deinit` are its
        // constructor and destructor; Rust publishes the first as
        // `Tally::new` and reaches the second only from `Drop`.
        api.handle("Tally", .{}).members(&.{
            tally.func("create", .{}),
            // Mutates, so Rust receives `&mut self`.
            tally.func("add", .{}),
            // Takes the value, so Rust receives `&self` -- a distinction Go
            // cannot express, since every Go receiver is `*Tally`.
            tally.func("peek", .{}),
            // Declares an error set, so Rust returns a `Result`. `add` and
            // `peek` do not, so they return their values.
            tally.func("checkedHalf", .{}),
            // The reading borrows from the tally, so Rust ties its lifetime
            // to this borrow.
            tally.func("borrowReading", .{ .returns = zigo.result.borrowed() }),
            // The caller owns the rendered bytes. Rust takes ownership of the
            // allocation; Go has to copy it and free it before returning.
            tally.func("render", .{ .returns = zigo.result.releasedBy(api.ref("freeRendered")) }),
            tally.func("deinit", .{}),
        }),
        // The view type. It owns nothing, so Rust gives it a lifetime and no
        // `Drop`.
        api.handle("Reading", .{}).members(&.{
            reading.func("total", .{}),
        }),
        // The release half of `render`. It has to be bound for the binding to
        // name it, but Rust does not publish it: `OwnedSlice`'s `Drop` owns
        // the release, and a public `free_rendered` beside it would be a
        // double free waiting to be written. Go publishes both.
        api.func("freeRendered", .{
            .params = &.{.{ .index = 0, .semantic = .utf8_string }},
        }),
        // Read by the Rust tests to prove `Drop` reached the destructor.
        api.func("liveBytes", .{}),
    },
});
