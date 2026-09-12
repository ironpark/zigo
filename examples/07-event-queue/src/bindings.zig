const zigo = @import("zigo");
const library = @import("event_queue");

const api = zigo.scope(library);
const Ticker = api.handle("Ticker", .{}).context();
const EventQueue = api.handle("EventQueue", .{}).context();
const Stream = api.handle("Stream", .{}).context();
const BorrowBox = api.handle("BorrowBox", .{}).context();
const BorrowView = api.handle("BorrowView", .{}).context();
const BorrowChild = api.handle("BorrowChild", .{}).context();
const Terminal = api.handle("Terminal", .{}).context();

const owned_samples = zigo.result.releasedBy(EventQueue.ref("freeSamples"));

const queue_binding = EventQueue.define(&.{
    EventQueue.func("create", .{
        .params = &.{
            .{ .index = 0, .go_name = "name", .semantic = .utf8_string },
            .{ .index = 1, .go_name = "capacity" },
            .{ .index = 2, .go_name = "policy" },
            zigo.param.callback(3, .{ .retention = .retained }),
        },
    }),
    EventQueue.func("clone", .{
        .returns = zigo.result.owned(),
        .params = &.{
            zigo.param.callback(1, .{ .retention = .retained }),
        },
    }),
    EventQueue.func("newStream", .{
        .role = .{
            .constructor = .{
                .type = Stream.typeRef(),
                .parent = .receiver,
                .receiver = .member,
            },
        },
    }),
    EventQueue.func("enqueue", .{}),
    EventQueue.func("mergeFrom", .{}),
    EventQueue.func("process", .{}),
    EventQueue.func("setObserver", .{
        .params = &.{
            zigo.param.callback(1, .{ .retention = .retained }),
        },
    }),
    EventQueue.func("name", .{ .returns = .{ .semantic = .utf8_string } }),
    EventQueue.func("sampleValues", .{}),
    EventQueue.func("sampleValuesChecked", .{}),
    EventQueue.func("selectionString", .{
        .returns = zigo.result.releasedBy(EventQueue.ref("freeSelectionString")),
    }),
    EventQueue.func("freeSelectionString", .{}),
    EventQueue.func("echoCString", .{}),
    EventQueue.func("sampleCString", .{}),
    EventQueue.func("extractPaths", .{
        .params = &.{
            .{ .index = 0, .semantic = .utf8_string },
        },
    }),
    EventQueue.func("extractSentinelSlices", .{}),
    EventQueue.func("extractSentinelPointers", .{}),
    EventQueue.func("extractSamples", .{ .returns = owned_samples }),
    EventQueue.func("extractSamplesChecked", .{ .returns = owned_samples }),
    EventQueue.func("freeSamples", .{}),
    EventQueue.func("extractLimits", .{ .returns = zigo.result.releasedBy(EventQueue.ref("freeLimits")) }),
    EventQueue.func("freeLimits", .{}),
    EventQueue.func("acceptStats", .{}),
    EventQueue.func("extractSamplesInto", .{
        .params = &.{
            zigo.param.output(1, .result),
        },
    }),
    EventQueue.func("limitsInto", .{
        .params = &.{
            zigo.param.output(1, .result),
        },
    }),
    EventQueue.func("estimate", .{ .params = &.{
        zigo.param.output(1, .result),
    } }),
    EventQueue.func("sampleStats", .{}),
    EventQueue.func("sampleLimits", .{}),
    EventQueue.func("len", .{}),
    EventQueue.func("capacity", .{}),
    EventQueue.func("policy", .{}),
    EventQueue.func("dropped", .{}),
    EventQueue.func("processed", .{}),
    EventQueue.func("stats", .{}),
    EventQueue.func("limits", .{}),
    EventQueue.func("applyLimits", .{}),
    EventQueue.func("clear", .{}),
    EventQueue.func("deinit", .{}),
});

const types_package = zigo.package(.{
    .path = "types",
    .doc = "Package types contains event-queue values and the standalone Ticker handle.",
    .declarations = &.{
        api.enumType("QueueSignal", .{ .exhaustive = false }).use(zigo.features.text, .{}),
        Ticker.define(&.{
            api.func("newTicker", .{ .role = .{ .constructor = .{ .type = Ticker.typeRef() } } }),
            api.func("freeTicker", .{ .role = .{ .destructor = Ticker.typeRef() } }),
            api.func("tickerAdvance", .{
                .name = "advance",
            }),
            api.func("tickerElapsed", .{
                .name = "elapsed",
            }),
        }),
        api.val("TickerInfo", .{}),
        api.func("liveTickers", .{}),
    },
});

pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .page_allocator,
    .declarations = &.{
        queue_binding,
        api.val("Stats", .{}),
        api.val("Limits", .{}),
        Stream.define(&.{
            Stream.func("capacity", .{}),
            api.func("freeStream", .{ .role = .{ .destructor = Stream.typeRef() } }),
        }),
        BorrowBox.define(&.{
            BorrowBox.func("create", .{}),
            BorrowBox.func("view", .{ .returns = zigo.result.borrowed() }),
            BorrowBox.func("deinit", .{}),
        }),
        BorrowView.define(&.{
            BorrowView.func("view", .{ .returns = zigo.result.borrowed() }),
            BorrowView.func("newChild", .{
                .role = .{
                    .constructor = .{
                        .type = BorrowChild.typeRef(),
                        .parent = .receiver,
                        .receiver = .member,
                    },
                },
            }),
            BorrowView.func("get", .{}),
            BorrowView.func("explode", .{}),
        }),
        BorrowChild.define(&.{
            BorrowChild.func("get", .{}),
            BorrowChild.func("deinit", .{ .role = .{ .destructor = BorrowChild.typeRef() } }),
        }),
        Terminal.define(&.{
            Terminal.func("init", .{
                .params = &.{
                    zigo.param.options(2, &.{ "rows", "max_scrollback_bytes" }, .{ .prefix = "" }),
                },
            }),
            Terminal.func("cols", .{}),
            Terminal.func("rows", .{}),
            Terminal.func("maxScrollbackBytes", .{}),
            Terminal.func("deinit", .{}),
        }),
        api.func("echoQueueSignal", .{}),
        zigo.session(.{
            .name = "Session",
            .primary = EventQueue.typeRef(),
            .children = &.{Stream.typeRef()},
            .doc = "Session owns an event queue and every stream it handed out.",
        }),
        api.func("liveBorrowChildren", .{}),
        api.func("inspectTicker", .{}),
        api.func("liveStreams", .{}),
        api.func("liveQueues", .{}),
        api.func("liveSamples", .{}),
        api.func("liveLimits", .{}),
        api.func("liveSelectionStrings", .{}),
        types_package,
    },
});
