const zigo = @import("zigo");
const library = @import("event_queue");

const api = zigo.scope(library);
const event_queue = api.in("EventQueue");
const stream = api.in("Stream");
const borrow_box = api.in("BorrowBox");
const borrow_view = api.in("BorrowView");
const borrow_child = api.in("BorrowChild");
const terminal = api.in("Terminal");

const owned_samples = zigo.result.releasedBy(event_queue.ref("freeSamples"));

const queue_binding = api.handle("EventQueue", .{}).members(&.{
    event_queue.function("create", .{
        .params = &.{
            .{ .index = 0, .go_name = "name", .semantic = .utf8_string },
            .{ .index = 1, .go_name = "capacity" },
            .{ .index = 2, .go_name = "policy" },
            zigo.param.callback(3, .{ .retention = .retained }),
        },
    }),
    event_queue.function("clone", .{
        .returns = zigo.result.owned(),
        .params = &.{
            zigo.param.callback(1, .{ .retention = .retained }),
        },
    }),
    event_queue.function("newStream", .{
        .role = .{
            .constructor = .{
                .type = api.typeRef("Stream"),
                .parent = .receiver,
                .receiver = .member,
            },
        },
    }),
    event_queue.function("enqueue", .{}),
    event_queue.function("mergeFrom", .{}),
    event_queue.function("process", .{}),
    event_queue.function("setObserver", .{
        .params = &.{
            zigo.param.callback(1, .{ .retention = .retained }),
        },
    }),
    event_queue.function("name", .{ .returns = .{ .semantic = .utf8_string } }),
    event_queue.function("sampleValues", .{}),
    event_queue.function("sampleValuesChecked", .{}),
    event_queue.function("selectionString", .{
        .returns = zigo.result.releasedBy(event_queue.ref("freeSelectionString")),
    }),
    event_queue.function("freeSelectionString", .{}),
    event_queue.function("echoCString", .{}),
    event_queue.function("sampleCString", .{}),
    event_queue.function("extractPaths", .{
        .params = &.{
            .{ .index = 0, .semantic = .utf8_string },
        },
    }),
    event_queue.function("extractSentinelSlices", .{}),
    event_queue.function("extractSentinelPointers", .{}),
    event_queue.function("extractSamples", .{ .returns = owned_samples }),
    event_queue.function("extractSamplesChecked", .{ .returns = owned_samples }),
    event_queue.function("freeSamples", .{}),
    event_queue.function("extractLimits", .{ .returns = zigo.result.releasedBy(event_queue.ref("freeLimits")) }),
    event_queue.function("freeLimits", .{}),
    event_queue.function("acceptStats", .{}),
    event_queue.function("extractSamplesInto", .{
        .params = &.{
            zigo.param.output(1, .result),
        },
    }),
    event_queue.function("limitsInto", .{
        .params = &.{
            zigo.param.output(1, .result),
        },
    }),
    event_queue.function("estimate", .{ .params = &.{
        zigo.param.output(1, .result),
    } }),
    event_queue.function("sampleStats", .{}),
    event_queue.function("sampleLimits", .{}),
    event_queue.function("len", .{}),
    event_queue.function("capacity", .{}),
    event_queue.function("policy", .{}),
    event_queue.function("dropped", .{}),
    event_queue.function("processed", .{}),
    event_queue.function("stats", .{}),
    event_queue.function("limits", .{}),
    event_queue.function("applyLimits", .{}),
    event_queue.function("clear", .{}),
    event_queue.function("deinit", .{}),
});

const types_package = zigo.package(.{
    .path = "types",
    .doc = "Package types contains event-queue values and the standalone Ticker handle.",
    .declarations = &.{
        api.enumeration("QueueSignal", .{ .exhaustive = false }).use(zigo.features.text, .{}),
        api.handle("Ticker", .{}).members(&.{
            api.function("newTicker", .{ .role = .{ .constructor = .{ .type = api.typeRef("Ticker") } } }),
            api.function("freeTicker", .{ .role = .{ .destructor = api.typeRef("Ticker") } }),
            api.function("tickerAdvance", .{
                .name = "advance",
                .role = .{ .method = api.typeRef("Ticker") },
            }),
            api.function("tickerElapsed", .{
                .name = "elapsed",
                .role = .{ .method = api.typeRef("Ticker") },
            }),
        }),
        api.value("TickerInfo", .{}),
        api.function("liveTickers", .{}),
    },
});

pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .page_allocator,
    .declarations = &.{
        queue_binding,
        api.value("Stats", .{}),
        api.value("Limits", .{}),
        api.handle("Stream", .{}).members(&.{
            stream.function("capacity", .{}),
        }),
        api.handle("BorrowBox", .{}).members(&.{
            borrow_box.function("create", .{}),
            borrow_box.function("view", .{ .returns = zigo.result.borrowed() }),
            borrow_box.function("deinit", .{}),
        }),
        api.handle("BorrowView", .{}).members(&.{
            borrow_view.function("view", .{ .returns = zigo.result.borrowed() }),
            borrow_view.function("newChild", .{
                .role = .{
                    .constructor = .{
                        .type = api.typeRef("BorrowChild"),
                        .parent = .receiver,
                        .receiver = .member,
                    },
                },
            }),
            borrow_view.function("get", .{}),
            borrow_view.function("explode", .{}),
        }),
        api.handle("BorrowChild", .{}).members(&.{
            borrow_child.function("get", .{}),
            borrow_child.function("deinit", .{ .role = .{ .destructor = api.typeRef("BorrowChild") } }),
        }),
        api.handle("Terminal", .{}).members(&.{
            terminal.function("init", .{
                .params = &.{
                    zigo.param.flatten(1, &.{ "cols", "rows", "max_scrollback_bytes" }),
                },
            }),
            terminal.function("cols", .{}),
            terminal.function("rows", .{}),
            terminal.function("maxScrollbackBytes", .{}),
            terminal.function("deinit", .{}),
        }),
        api.function("echoQueueSignal", .{}),
        api.function("liveBorrowChildren", .{}),
        api.function("freeStream", .{ .role = .{ .destructor = api.typeRef("Stream") } }),
        api.function("inspectTicker", .{}),
        api.function("liveStreams", .{}),
        api.function("liveQueues", .{}),
        api.function("liveSamples", .{}),
        api.function("liveLimits", .{}),
        api.function("liveSelectionStrings", .{}),
        types_package,
    },
});
