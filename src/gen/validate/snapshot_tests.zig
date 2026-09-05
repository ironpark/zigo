//! Whole-pipeline tests: the rendered text of every implemented diagnostic.
const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");
const validate = @import("validate.zig");

test "implemented diagnostic snapshots are stable" {
    var void_node: semantic.TypeNode = .{ .void = {} };
    var pointer_node: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Thing" } };
    var pointer_slice_node: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &pointer_node } };
    var callback_return: semantic.TypeNode = .{ .void = {} };
    var sample_element: semantic.TypeNode = .{ .int = .{ .bits = 16, .signed = true } };
    const config_element: semantic.TypeNode = .{ .value_struct = .{ .ref = "Config" } };
    var callback_params = [_]semantic.TypeNode{config_element};
    const struct_callback: semantic.TypeNode = .{ .callback = .{ .params = &callback_params, .@"return" = &callback_return, .has_userdata = false } };
    var byte_element: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var byte_slice_node: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &byte_element } };
    var word_element: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const word_slice_node: semantic.TypeNode = .{ .slice = .{ .@"const" = false, .element = &word_element } };
    var optional_word_node: semantic.TypeNode = .{ .optional = .{ .child = &word_element } };
    const count_node: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    var wide_element: semantic.TypeNode = .{ .int = .{ .bits = 21, .signed = false } };
    const wide_slice_node: semantic.TypeNode = .{ .slice = .{ .@"const" = true, .element = &wide_element } };
    var wide_callback_params = [_]semantic.TypeNode{.{ .int = .{ .bits = 21, .signed = false } }};
    const cases = [_]struct { document: semantic.Semantic, snapshot: []const u8 }{
        .{ .document = .{
            .functions = &.{.{
                .name = "unstable",
                .params = &.{},
                .@"return" = .{ .error_union = .{ .anyerror = true, .error_set = &.{}, .payload = &void_node } },
                .symbol = "zg_unstable",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO001]: cannot expose an anyerror return with stable ABI codes\n  --> semantic.json (unstable)\n  hint: use an explicit error set in the Zig function signature\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .exhaustive = false, .kind = .@"enum", .name = "Open" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO002]: cannot expose a non-exhaustive enum\n  --> semantic.json (Open)\n  hint: make the enum exhaustive, or register it with `.exhaustive = false`\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"enum", .name = "Closed", .open = true }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO029]: open-enum opt-in applied to an exhaustive enum\n  --> semantic.json (Closed)\n  hint: remove `.exhaustive = false`, or make the Zig enum non-exhaustive\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "configure",
                .params = &.{.{ .name = "config", .type = .{ .value_struct = .{ .ref = "Config" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_configure",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .value_struct, .name = "Config" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO003]: cannot pass a non-extern struct by value\n  --> semantic.json (configure)\n  hint: declare it as `extern struct`, or expose it as opaque\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "setCallback",
                .params = &.{.{ .name = "callback", .type = .{ .callback = .{ .c_callconv = false, .has_userdata = false, .params = &.{}, .@"return" = &callback_return } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_set_callback",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO004]: function pointer does not use the C calling convention\n  --> semantic.json (setCallback)\n  hint: declare the callback with `callconv(.c)`\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "pointers",
                .params = &.{.{ .name = "values", .type = .{ .slice = .{ .@"const" = true, .element = &pointer_node } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_pointers",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO005]: slice element type contains a pointer\n  --> semantic.json (pointers)\n  hint: pass scalar elements or opaque handle values instead of Go pointers\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "takePointers",
                .params = &.{},
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &pointer_node } },
                .symbol = "zg_take_pointers",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO005]: slice element type contains a pointer\n  --> semantic.json (takePointers)\n  hint: return scalar, enum, or extern-struct elements instead of Go pointers\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "takePointersChecked",
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &pointer_slice_node } },
                .symbol = "zg_take_pointers_checked",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO005]: slice element type contains a pointer\n  --> semantic.json (takePointersChecked)\n  hint: return scalar, enum, or extern-struct elements instead of Go pointers\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "consume",
                .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Value" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_consume",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{
                .{ .fields = &.{.{ .name = "bytes", .type = byte_slice_node, .value = 0 }}, .kind = .tagged_union, .name = "Value", .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } } },
                .{ .fields = &.{.{ .name = "bytes", .value = 0 }}, .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
            },
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO006]: cannot pass a tagged union by value\n  --> semantic.json (consume)\n  hint: variant `bytes` has an unsupported value payload; omit it with `.omit_variants` or use void, scalar, enum, packed struct, or extern struct payloads\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "consume",
                .params = &.{.{ .name = "value", .type = .{ .value_struct = .{ .ref = "Value" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_consume",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{
                .{ .fields = &.{.{ .name = "child", .type = pointer_node, .value = 0 }}, .kind = .tagged_union, .name = "Value", .tag_type = .{ .@"enum" = .{ .ref = "ValueTag" } } },
                .{ .fields = &.{.{ .name = "child", .value = 0 }}, .kind = .@"enum", .name = "ValueTag", .tag_type = .{ .int = .{ .bits = 8, .signed = false } } },
                .{ .kind = .@"opaque", .name = "Thing" },
            },
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO006]: cannot pass a tagged union by value\n  --> semantic.json (consume)\n  hint: variant `child` has an unsupported value payload; omit it with `.omit_variants` or use void, scalar, enum, packed struct, or extern struct payloads\n" },
        .{ .document = .{
            .functions = &.{
                .{ .name = "lookupID", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "ignored" },
                .{ .name = "lookup_id", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "ignored" },
            },
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO036]: C identifier `zg_lookup_id` collides between function `lookupID` and function `lookup_id`\n  --> semantic.json (function `lookup_id`)\n  hint: give one declaration a distinct `.name`, or choose a different binding `.prefix`\n  note: consider .name = \"LookupIDBinding\" on function lookup_id\n" },
        .{ .document = .{
            .functions = &.{.{
                .has_comptime_params = true,
                .name = "generic",
                .params = &.{},
                .@"return" = .{ .void = {} },
                .symbol = "zg_generic",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO008]: cannot expose a function with comptime parameters\n  --> semantic.json (generic)\n  hint: bind a concrete specialization instead of the generic function\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "remember",
                .params = &.{.{ .name = "thing", .retention = .retained, .type = .{ .opaque_ptr = .{ .@"const" = true, .nullable = false, .ref = "Thing" } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_remember",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "Thing" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO009]: retained pointer has no matching release function\n  --> semantic.json (remember)\n  hint: expose a release, clear, close, destroy, or deinit function for the retained value\n  note: consider exposing `pub fn release() void` alongside `remember`\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{
                .{
                    .fields = &.{
                        .{ .name = "none", .type = .{ .void = {} }, .value = 0 },
                        .{ .name = "samples", .type = .{ .slice = .{ .@"const" = true, .element = &sample_element } }, .value = 1 },
                    },
                    .kind = .tagged_union,
                    .name = "Signal",
                    .tag_type = .{ .@"enum" = .{ .ref = "SignalTag" } },
                    .access = .snapshot,
                },
                .{
                    .fields = &.{ .{ .name = "none", .value = 0 }, .{ .name = "samples", .value = 1 } },
                    .kind = .@"enum",
                    .name = "SignalTag",
                    .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
                },
            },
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO011]: tagged union variant cannot be mirrored into a value snapshot\n  --> semantic.json (samples)\n  hint: use `.access = .projection`, or give every variant a void, bool, integer, float, or enum payload and a name other than `tag`\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{
                    .{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } },
                    .{ .name = "label", .type = .{ .slice = .{ .@"const" = true, .element = &sample_element } } },
                },
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Config",
            }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO012]: extern struct cannot cross the C ABI\n  --> semantic.json (label)\n  hint: give every field a bool, integer, float, registered enum, or nested `extern struct` type; an empty struct has no C representation\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "visitAll",
                .params = &.{.{ .name = "visitor", .type = struct_callback }},
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{.{ .name = "width", .type = .{ .int = .{ .bits = 32, .signed = true } } }},
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Config",
            }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO013]: extern struct is only supported as a whole parameter or return value\n  --> semantic.json (visitAll)\n  hint: pass the struct on its own or as a direct slice element; optional and callback signatures are not supported\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "takeName",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .slice = .{ .@"const" = true, .element = &byte_element } },
                .symbol = "zg_take_name",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO016]: caller-owned slice return has no matching release function\n  --> semantic.json (takeName)\n  hint: add `.release = \"<Type>.<fn>\"` naming an exposed `fn(slice) void` that takes exactly the returned slice type\n" },
        .{ .document = .{
            .functions = &.{
                .{
                    .name = "takeBytes",
                    .ownership = .caller,
                    .params = &.{},
                    .release = "freeWords",
                    .@"return" = .{ .slice = .{ .@"const" = true, .element = &byte_element } },
                    .symbol = "zg_take_bytes",
                },
                .{
                    .name = "freeWords",
                    .params = &.{.{ .name = "words", .type = .{ .slice = .{ .@"const" = false, .element = &word_element } } }},
                    .@"return" = .{ .void = {} },
                    .symbol = "zg_free_words",
                },
            },
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO016]: caller-owned slice return has no matching release function\n  --> semantic.json (takeBytes)\n  hint: add `.release = \"<Type>.<fn>\"` naming an exposed `fn(slice) void` that takes exactly the returned slice type\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "takeNameChecked",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &byte_slice_node } },
                .symbol = "zg_take_name_checked",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO016]: caller-owned slice return has no matching release function\n  --> semantic.json (takeNameChecked)\n  hint: add `.release = \"<Type>.<fn>\"` naming an exposed `fn(slice) void` that takes exactly the returned slice type\n" },
        .{ .document = .{
            .functions = &.{
                .{
                    .name = "takeBytesChecked",
                    .ownership = .caller,
                    .params = &.{},
                    .release = "freeWords",
                    .@"return" = .{ .error_union = .{ .error_set = &.{"Invalid"}, .payload = &byte_slice_node } },
                    .symbol = "zg_take_bytes_checked",
                },
                .{
                    .name = "freeWords",
                    .params = &.{.{ .name = "words", .type = .{ .slice = .{ .@"const" = false, .element = &word_element } } }},
                    .@"return" = .{ .void = {} },
                    .symbol = "zg_free_words",
                },
            },
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO016]: caller-owned slice return has no matching release function\n  --> semantic.json (takeBytesChecked)\n  hint: add `.release = \"<Type>.<fn>\"` naming an exposed `fn(slice) void` that takes exactly the returned slice type\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "openThing",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Thing" } },
                .symbol = "zg_open_thing",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "Thing" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO015]: caller-owned return has no constructed handle to hand over\n  --> semantic.json (openThing)\n  hint: return a pointer to an opaque type that has both a constructor and a destructor, or drop `.returns = .caller`\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "readInto",
                .params = &.{.{ .name = "source", .type = word_slice_node, .written = .@"return" }},
                .@"return" = count_node,
                .symbol = "zg_read_into",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO017]: written hint declared on a parameter that is not an output slice\n  --> semantic.json (readInto)\n  hint: add `.direction = .out` to the parameter, or drop `.written`\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "fillInto",
                .params = &.{.{ .direction = .out, .name = "dst", .type = word_slice_node, .written = .@"return" }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_fill_into",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO017]: `.written = .return` needs a `usize` result to report the count\n  --> semantic.json (fillInto)\n  hint: return `usize` or `!usize` from the function, or use the default `.written = .all`\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "codepointWidth",
                .namespace = "unicode",
                .params = &.{.{ .name = "cp", .type = .{ .int = .{ .bits = 128, .signed = false } } }},
                .@"return" = .{ .int = .{ .bits = 8, .signed = true } },
                .symbol = "zg_unicode_codepoint_width",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO018]: unsupported integer width `u128` in parameter `cp`\n  --> semantic.json (unicode.codepointWidth)\n  hint: use an integer of 64 bits or fewer\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "widths",
                .params = &.{.{ .name = "cps", .type = wide_slice_node }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_widths",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO045]: narrow integer slice parameter `cps` needs temporary storage\n  --> semantic.json (widths)\n  hint: set `.allocator = .c_allocator`, `.page_allocator`, `.smp_allocator`, or a declaration path in the binding\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "onCodepoint",
                .params = &.{.{ .name = "callback", .type = .{ .callback = .{ .has_userdata = false, .params = &wide_callback_params, .@"return" = &callback_return } } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_on_codepoint",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO018]: cannot promote integer width `u21` in callback parameter 0 of parameter `callback`\n  --> semantic.json (onCodepoint)\n  hint: zigo widens narrow integers only as whole values or direct non-sentinel slice elements; value-struct fields, union payloads, callbacks, and nested slices must use 8, 16, 32, or 64 bits\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{.{ .name = "codepoint", .type = .{ .int = .{ .bits = 21, .signed = false } } }},
                .kind = .value_struct,
                .layout = .@"extern",
                .name = "Cell",
            }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO018]: cannot promote integer width `u21` in field `codepoint`\n  --> semantic.json (Cell)\n  hint: an `extern struct` is mirrored into C field by field; use an 8, 16, 32, or 64-bit integer here\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "extended",
                .params = &.{},
                .@"return" = .{ .float = .{ .bits = 80 } },
                .symbol = "zg_extended",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO018]: unsupported float width `f80` in the return value\n  --> semantic.json (extended)\n  hint: use `f32` or `f64`\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "maybe",
                .params = &.{.{ .name = "value", .type = .{ .optional = .{ .child = &optional_word_node } } }},
                .@"return" = .{ .void = {} },
                .receiver = "Thing",
                .symbol = "zg_thing_maybe",
            }},
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "Thing" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO019]: unsupported optional in parameter `value`\n  --> semantic.json (Thing.maybe)\n  hint: zigo carries an optional only as a whole parameter, return value, or error payload, and only over a bool, integer, float, enum, extern struct, or pointer to a declared opaque type\n" },
        .{ .document = .{
            .ir_version = 2,
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO020]: semantic document uses an unsupported IR version\n  --> semantic.json (ir_version)\n  hint: regenerate semantic.json with a matching zigo version\n" },
        .{ .document = .{
            .package = "",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: semantic document has an empty package name\n  --> semantic.json (package)\n  hint: give the binding a package name\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: semantic document has an empty symbol prefix\n  --> semantic.json (prefix)\n  hint: give the binding a symbol prefix\n" },
        .{ .document = .{
            .functions = &.{.{ .name = "", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_" }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: exposed function has an empty name\n  --> semantic.json (functions)\n  hint: expose a named declaration\n" },
        // `@typeName` of a comptime-generated enum ends in the slice
        // expression that built it, and the last dotted segment of that is
        // not a name at all.
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{ .{ .name = "block", .value = 0 }, .{ .name = "bar", .value = 1 } },
                .kind = .@"enum",
                .name = "4])",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
                .zig_path = "vt.lib.Enum([_][]const u8{ \"block\", \"bar\" }[0..4])",
            }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: registered type name `4])` from Zig type `vt.lib.Enum([_][]const u8{ \"block\", \"bar\" }[0..4])` is not a valid Go identifier\n  --> semantic.json (4]))\n  hint: register the type in `.types` with an explicit `.name` that is a Go identifier\n  note: consider .name = \"Enum4\" on type vt.lib.Enum([_][]const u8{ \"block\", \"bar\" }[0..4])\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{
                .fields = &.{.{ .name = "_", .value = 0 }},
                .kind = .@"enum",
                .name = "Mode",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: enum tag `_` is not a valid Go identifier\n  --> semantic.json (Mode)\n  hint: rename the declaration in Zig so its name converts to a Go identifier\n  note: consider renaming enum tag `_` to `value`\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "open",
                .params = &.{.{ .injected = .allocator, .name = "alloc", .type = .{ .void = {} } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_open",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO022]: parameter `alloc` needs a `std.mem.Allocator` the binding has not named\n  --> semantic.json (open)\n  hint: set `.allocator = .c_allocator`, `.page_allocator`, `.smp_allocator`, or a declaration path in the binding\n" },
        .{ .document = .{
            .functions = &.{.{
                .name = "flush",
                .params = &.{.{ .injected = .io, .name = "io", .type = .{ .void = {} } }},
                .@"return" = .{ .void = {} },
                .symbol = "zg_flush",
            }},
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO022]: parameter `io` needs a `std.Io` the binding has not named\n  --> semantic.json (flush)\n  hint: set `.io = \"<declaration path>\"` in the binding\n" },
        .{ .document = .{
            .package = "bad",
            .prefix = "zg",
            .types = &.{.{ .kind = .@"opaque", .name = "range" }},
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO021]: registered type name `range` is not a valid Go identifier\n  --> semantic.json (range)\n  hint: register the type in `.types` with an explicit `.name` that is a Go identifier\n  note: consider .name = \"Range\" on type range\n" },
        // `open` in namespace `File` and `open` in namespace `Socket` have no
        // receiver, so `ZIGO007`'s symbol check tells them apart (their C
        // symbols carry the namespace) but the public Go layer drops it: both
        // resolve to the top-level function `Open`.
        .{ .document = .{
            .functions = &.{
                .{ .name = "open", .namespace = "File", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_file_open" },
                .{ .name = "open", .namespace = "Socket", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_socket_open" },
            },
            .package = "bad",
            .prefix = "zg",
            .zig_version = "0.16.0",
        }, .snapshot = "error[ZIGO024]: public Go name `Open` collides between `File.open` and `Socket.open`\n  --> semantic.json (Socket.open)\n  hint: rename one declaration, or give it a `.name` that resolves to a different Go identifier\n  note: consider .name = \"OpenBinding\" on function Socket.open\n" },
    };
    // A located diagnostic names the declaration and the parameter it found,
    // so its strings come from the arena the caller is expected to pass.
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    for (cases) |case| {
        const issue = (try validate.findIssue(scratch.allocator(), case.document)) orelse return error.MissingDiagnostic;
        const rendered = try issue.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings(case.snapshot, rendered);
    }
}

test "child-of-receiver metadata on a non-receiver constructor has a stable diagnostic" {
    var child: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Child" } };
    const document: semantic.Semantic = .{
        .constructors = &.{.{ .type = "Child", .init = "newChild", .deinit = "freeChild" }},
        .functions = &.{
            .{
                .child_of_receiver = true,
                .go_owner = "Child",
                .name = "newChild",
                .ownership = .caller,
                .params = &.{},
                .@"return" = .{ .error_union = .{ .error_set = &.{}, .payload = &child } },
                .symbol = "zg_new_child",
            },
            .{ .name = "freeChild", .params = &.{}, .receiver = "Child", .@"return" = .{ .void = {} }, .symbol = "zg_child_free_child" },
        },
        .package = "bad",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "Child" }},
        .zig_version = "0.16.0",
    };
    const issue = (try validate.findIssue(std.testing.allocator, document)) orelse return error.MissingDiagnostic;
    const rendered = try issue.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        "error[ZIGO030]: child-of-receiver metadata requires a receiver constructor\n" ++
            "  --> semantic.json (newChild)\n" ++
            "  hint: use `.child_of_receiver = true` only on a constructor method that returns its paired caller-owned handle\n",
        rendered,
    );
}

test "borrowed return ownership diagnostics are stable" {
    const pointer: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "View" } };
    const base: semantic.Semantic = .{
        .package = "bad",
        .prefix = "zg",
        .types = &.{.{ .kind = .@"opaque", .name = "View" }},
        .zig_version = "0.16.0",
    };
    const cases = [_]struct { function: semantic.SemanticFn, snapshot: []const u8 }{
        .{ .function = .{
            .borrowed_return = true,
            .name = "view",
            .params = &.{},
            .@"return" = pointer,
            .symbol = "zg_view",
        }, .snapshot = "error[ZIGO033]: borrowed return has no receiver to own its lifetime\n  --> semantic.json (view)\n  hint: use `.returns = .borrowed` only on a method, or use `.returns = .caller` with a constructor and destructor\n" },
        .{ .function = .{
            .borrowed_return = true,
            .name = "count",
            .params = &.{},
            .receiver = "Owner",
            .@"return" = .{ .int = .{ .bits = 32, .signed = false } },
            .symbol = "zg_owner_count",
        }, .snapshot = "error[ZIGO034]: borrowed return is not a registered opaque handle\n  --> semantic.json (count)\n  hint: return `*T`, `?*T`, `!*T`, or `!?*T` where T is a registered opaque type, or drop `.returns = .borrowed`\n" },
        .{ .function = .{
            .name = "view",
            .params = &.{},
            .receiver = "Owner",
            .@"return" = pointer,
            .symbol = "zg_owner_view",
        }, .snapshot = "error[ZIGO035]: opaque handle return has no explicit ownership\n  --> semantic.json (view)\n  hint: add `.returns = .borrowed` for a receiver-owned view, or pair `.returns = .caller` with its constructor and destructor\n" },
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    for (cases) |case| {
        var document = base;
        document.functions = @as(*const [1]semantic.SemanticFn, &case.function);
        const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
        const rendered = try issue.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings(case.snapshot, rendered);
    }
}

test "C typedef and function symbol collisions have a stable diagnostic" {
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "select",
            .params = &.{},
            .receiver = "Search",
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .package = "bad",
        .prefix = "zg",
        .types = &.{
            .{ .kind = .@"opaque", .name = "Search" },
            .{
                .fields = &.{.{ .name = "none", .value = 0 }},
                .kind = .@"enum",
                .name = "SearchSelect",
                .tag_type = .{ .int = .{ .bits = 8, .signed = false } },
            },
        },
        .zig_version = "0.16.0",
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
    const rendered = try issue.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        "error[ZIGO036]: C identifier `zg_search_select` collides between type `SearchSelect` and function `Search.select`\n" ++
            "  --> semantic.json (function `Search.select`)\n" ++
            "  hint: give one declaration a distinct `.name`, or choose a different binding `.prefix`\n" ++
            "  note: consider .name = \"SearchSelectKind\" on type SearchSelect\n",
        rendered,
    );
}

test "interface diagnostics have stable snapshots" {
    const interfaces = @import("interfaces.zig");
    const cases = [_]struct { document: semantic.Semantic, snapshot: []const u8 }{
        .{ .document = interfaces.batchDocument(.{ .interfaces = &.{.{ .methods = &.{"len"}, .name = "batch-set", .types = &.{"IntBatch"} }} }), .snapshot = "error[ZIGO049]: interface name is not a Go identifier\n  --> semantic.json (batch-set)\n  hint: give the interface a `.name` that is a valid exported Go identifier\n" },
        .{ .document = interfaces.batchDocument(.{ .interfaces = &.{.{ .methods = &.{"len"}, .name = "IntBatch", .types = &.{"IntBatch"} }} }), .snapshot = "error[ZIGO024]: public Go name `IntBatch` collides between interface `IntBatch` and type `IntBatch`\n  --> semantic.json (IntBatch)\n  hint: give the interface a `.name` that resolves to a different Go identifier\n" },
        .{ .document = interfaces.batchDocument(.{ .interfaces = &.{.{ .methods = &.{"len"}, .name = "Batch", .types = &.{ "IntBatch", "Missing" } }} }), .snapshot = "error[ZIGO049]: interface lists `Missing`, which is not a registered opaque handle\n  --> semantic.json (Batch)\n  hint: list only types registered with `.repr = .opaque`\n" },
        .{ .document = interfaces.batchDocument(.{ .interfaces = &.{.{ .methods = &.{"len"}, .name = "Batch", .types = &.{ "IntBatch", "IntBatch" } }} }), .snapshot = "error[ZIGO049]: interface lists `IntBatch` twice\n  --> semantic.json (Batch)\n  hint: list each implementing type once\n" },
        .{ .document = interfaces.batchDocument(.{ .interfaces = &.{.{ .methods = &.{ "len", "clear" }, .name = "Batch", .types = &.{ "IntBatch", "FloatBatch" } }} }), .snapshot = "error[ZIGO049]: type `IntBatch` has no exposed method `clear`\n  --> semantic.json (Batch)\n  hint: expose the method on every listed type, or drop it from `.methods`\n" },
        // The destructor is not a method a live handle offers.
        .{ .document = interfaces.batchDocument(.{ .interfaces = &.{.{ .methods = &.{"deinit"}, .name = "Batch", .types = &.{"IntBatch"} }} }), .snapshot = "error[ZIGO049]: type `IntBatch` has no exposed method `deinit`\n  --> semantic.json (Batch)\n  hint: expose the method on every listed type, or drop it from `.methods`\n" },
        .{ .document = interfaces.batchDocument(.{ .interfaces = &.{.{ .methods = &.{ "len", "len" }, .name = "Batch", .types = &.{"IntBatch"} }} }), .snapshot = "error[ZIGO049]: interface lists method `len` twice\n  --> semantic.json (Batch)\n  hint: list each method once\n" },
        .{ .document = interfaces.batchDocument(.{
            .constructors = &.{.{ .deinit = "deinit", .init = "create", .type = "IntBatch" }},
            .functions = &(interfaces.batch_functions[0..3].* ++ interfaces.batch_functions[4..5].*),
        }), .snapshot = "error[ZIGO049]: interface includes io.Closer but `FloatBatch` has no constructor pair\n  --> semantic.json (Batch)\n  hint: pair the type with a constructor and destructor, or set `.closer = false`\n" },
    };
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    for (cases) |case| {
        const issue = (try validate.findIssue(scratch.allocator(), case.document)) orelse return error.MissingDiagnostic;
        const rendered = try issue.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings(case.snapshot, rendered);
    }
}

test "an interface must stay in the package of its types" {
    const interfaces = @import("interfaces.zig");
    const split_types = [_]semantic.TypeDecl{
        .{ .kind = .@"opaque", .name = "IntBatch", .package = "ints" },
        .{ .kind = .@"opaque", .name = "FloatBatch" },
    };
    var document = interfaces.batchDocument(.{
        .extra_types = &split_types,
        .packages = &.{.{ .name = "ints", .path = "ints" }},
        .interfaces = &.{.{ .closer = false, .methods = &.{"len"}, .name = "Batch", .package = "ints", .types = &.{ "IntBatch", "FloatBatch" } }},
    });
    // The split document also has to keep IntBatch's methods in its package.
    var functions: [6]semantic.SemanticFn = undefined;
    for (document.functions, 0..) |function, index| {
        functions[index] = function;
        if (std.mem.eql(u8, function.receiver orelse function.namespace orelse "", "IntBatch")) functions[index].package = "ints";
    }
    document.functions = &functions;
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
    const rendered = try issue.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        "error[ZIGO049]: interface and `FloatBatch` are in different public packages\n  --> semantic.json (Batch)\n  hint: assign the interface's types to one package\n",
        rendered,
    );
}
