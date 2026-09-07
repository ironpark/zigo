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
    EventQueue.function("create", .{
        .params = &.{
            .{ .index = 0, .go_name = "name", .semantic = .utf8_string },
            .{ .index = 1, .go_name = "capacity" },
            .{ .index = 2, .go_name = "policy" },
            zigo.param.callback(3, .{ .retention = .retained }),
        },
    }),
    EventQueue.function("clone", .{
        .returns = zigo.result.owned(),
        .params = &.{
            zigo.param.callback(1, .{ .retention = .retained }),
        },
    }),
    EventQueue.function("newStream", .{
        .role = .{
            .constructor = .{
                .type = Stream.typeRef(),
                .parent = .receiver,
                .receiver = .member,
            },
        },
    }),
    EventQueue.function("enqueue", .{}),
    EventQueue.function("mergeFrom", .{}),
    EventQueue.function("process", .{}),
    EventQueue.function("setObserver", .{
        .params = &.{
            zigo.param.callback(1, .{ .retention = .retained }),
        },
    }),
    EventQueue.function("name", .{ .returns = .{ .semantic = .utf8_string } }),
    EventQueue.function("sampleValues", .{}),
    EventQueue.function("sampleValuesChecked", .{}),
    EventQueue.function("selectionString", .{
        .returns = zigo.result.releasedBy(EventQueue.ref("freeSelectionString")),
    }),
    EventQueue.function("freeSelectionString", .{}),
    EventQueue.function("echoCString", .{}),
    EventQueue.function("sampleCString", .{}),
    EventQueue.function("extractPaths", .{
        .params = &.{
            .{ .index = 0, .semantic = .utf8_string },
        },
    }),
    EventQueue.function("extractSentinelSlices", .{}),
    EventQueue.function("extractSentinelPointers", .{}),
    EventQueue.function("extractSamples", .{ .returns = owned_samples }),
    EventQueue.function("extractSamplesChecked", .{ .returns = owned_samples }),
    EventQueue.function("freeSamples", .{}),
    EventQueue.function("extractLimits", .{ .returns = zigo.result.releasedBy(EventQueue.ref("freeLimits")) }),
    EventQueue.function("freeLimits", .{}),
    EventQueue.function("acceptStats", .{}),
    EventQueue.function("extractSamplesInto", .{
        .params = &.{
            zigo.param.output(1, .result),
        },
    }),
    EventQueue.function("limitsInto", .{
        .params = &.{
            zigo.param.output(1, .result),
        },
    }),
    EventQueue.function("estimate", .{ .params = &.{
        zigo.param.output(1, .result),
    } }),
    EventQueue.function("sampleStats", .{}),
    EventQueue.function("sampleLimits", .{}),
    EventQueue.function("len", .{}),
    EventQueue.function("capacity", .{}),
    EventQueue.function("policy", .{}),
    EventQueue.function("dropped", .{}),
    EventQueue.function("processed", .{}),
    EventQueue.function("stats", .{}),
    EventQueue.function("limits", .{}),
    EventQueue.function("applyLimits", .{}),
    EventQueue.function("clear", .{}),
    EventQueue.function("deinit", .{}),
});

const types_package = zigo.package(.{
    .path = "types",
    .doc = "Package types contains event-queue values and the standalone Ticker handle.",
    .declarations = &.{
        api.enumeration("QueueSignal", .{ .exhaustive = false }).use(zigo.features.text, .{}),
        Ticker.define(&.{
            api.function("newTicker", .{ .role = .{ .constructor = .{ .type = Ticker.typeRef() } } }),
            api.function("freeTicker", .{ .role = .{ .destructor = Ticker.typeRef() } }),
            api.function("tickerAdvance", .{
                .name = "advance",
            }),
            api.function("tickerElapsed", .{
                .name = "elapsed",
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
        Stream.define(&.{
            Stream.function("capacity", .{}),
            api.function("freeStream", .{ .role = .{ .destructor = Stream.typeRef() } }),
        }),
        BorrowBox.define(&.{
            BorrowBox.function("create", .{}),
            BorrowBox.function("view", .{ .returns = zigo.result.borrowed() }),
            BorrowBox.function("deinit", .{}),
        }),
        BorrowView.define(&.{
            BorrowView.function("view", .{ .returns = zigo.result.borrowed() }),
            BorrowView.function("newChild", .{
                .role = .{
                    .constructor = .{
                        .type = BorrowChild.typeRef(),
                        .parent = .receiver,
                        .receiver = .member,
                    },
                },
            }),
            BorrowView.function("get", .{}),
            BorrowView.function("explode", .{}),
        }),
        BorrowChild.define(&.{
            BorrowChild.function("get", .{}),
            BorrowChild.function("deinit", .{ .role = .{ .destructor = BorrowChild.typeRef() } }),
        }),
        Terminal.define(&.{
            Terminal.function("init", .{
                .params = &.{
                    zigo.param.flatten(1, &.{ "cols", "rows", "max_scrollback_bytes" }),
                },
            }),
            Terminal.function("cols", .{}),
            Terminal.function("rows", .{}),
            Terminal.function("maxScrollbackBytes", .{}),
            Terminal.function("deinit", .{}),
        }),
        api.function("echoQueueSignal", .{}),
        api.function("liveBorrowChildren", .{}),
        api.function("inspectTicker", .{}),
        api.function("liveStreams", .{}),
        api.function("liveQueues", .{}),
        api.function("liveSamples", .{}),
        api.function("liveLimits", .{}),
        api.function("liveSelectionStrings", .{}),
        types_package,
    },
});
