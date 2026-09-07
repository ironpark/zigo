const zigo = @import("zigo");
const library = @import("event_queue");

pub const bindings = zigo.define(.{
    // `freeLimits` takes its allocator as a parameter; naming it here is what
    // lets the shim fill it in rather than exposing it to Go.
    .allocator = .page_allocator,
    .root = library,
    .packages = &.{
        .{
            .path = "types",
            .doc = "Package types contains event-queue values and the standalone Ticker handle.",
            // The prefix pattern selects QueueSignal without enumerating future
            // Queue* values. Closure follows newTicker's lifecycle target and
            // pulls in Ticker, which no longer needs to be listed by hand.
            .types = &.{ "Queue*", "TickerInfo" },
            .functions = &.{ "root.liveTickers", "root.newTicker" },
            .closure = true,
        },
    },
    .types = &.{
        .{ .handle = .{ .type = library.EventQueue } },
        .{ .value = .{ .type = library.Stats } },
        .{ .value = .{ .type = library.Limits } },
        .{ .enumeration = .{ .type = library.QueueSignal, .exhaustive = false, .text = true } },
        .{ .handle = .{ .type = library.Ticker } },
        .{ .value = .{ .type = library.TickerInfo } },
        .{ .handle = .{ .type = library.Stream } },
        .{ .handle = .{ .type = library.BorrowBox } },
        .{ .handle = .{ .type = library.BorrowView } },
        .{ .handle = .{ .type = library.BorrowChild } },
        .{ .handle = .{ .type = library.Terminal } },
    },
    .functions = &.{
        .{ .path = "root.echoQueueSignal", .params = &.{.{ .name = "signal" }} },
        .{
            .path = "EventQueue.create",
            .params = &.{ .{ .name = "name", .semantic = .utf8_string }, .{ .name = "capacity" }, .{ .name = "policy" }, .{ .name = "observer", .retention = .retained }, .{ .name = "userdata" } },
        },
        .{
            .path = "EventQueue.clone",
            .params = &.{ .{ .name = "observer", .retention = .retained }, .{ .name = "userdata" } },
            .returns = .{ .ownership = .caller },
        },
        .{ .path = "EventQueue.newStream", .constructs = library.Stream, .child_of_receiver = true },
        .{ .path = "BorrowBox.create", .params = &.{.{ .name = "value" }} },
        .{ .path = "BorrowBox.view", .returns = .{ .ownership = .borrowed } },
        .{ .path = "BorrowBox.deinit" },
        .{ .path = "BorrowView.view", .returns = .{ .ownership = .borrowed } },
        .{ .path = "BorrowView.newChild", .constructs = library.BorrowChild, .child_of_receiver = true },
        .{ .path = "BorrowView.get" },
        .{ .path = "BorrowView.explode" },
        .{ .path = "BorrowChild.get" },
        .{ .path = "BorrowChild.deinit", .destroys = library.BorrowChild },
        .{ .path = "root.liveBorrowChildren" },
        .{
            .path = "Terminal.init",
            .params = &.{.{ .name = "options", .flatten = &.{ "cols", "rows", "max_scrollback_bytes" } }},
        },
        .{ .path = "Terminal.cols" },
        .{ .path = "Terminal.rows" },
        .{ .path = "Terminal.maxScrollbackBytes" },
        .{ .path = "Terminal.deinit" },
        .{ .path = "Stream.capacity" },
        .{ .path = "root.freeStream", .destroys = library.Stream },
        .{ .path = "EventQueue.enqueue", .params = &.{ .{ .name = "id" }, .{ .name = "value" } } },
        .{ .path = "EventQueue.mergeFrom", .params = &.{.{ .name = "source" }} },
        .{ .path = "EventQueue.process", .params = &.{.{ .name = "limit" }} },
        .{
            .path = "EventQueue.setObserver",
            .params = &.{ .{ .name = "observer", .retention = .retained }, .{ .name = "userdata" } },
        },
        .{ .path = "EventQueue.name", .returns = .{ .semantic = .utf8_string } },
        .{ .path = "EventQueue.sampleValues" },
        .{ .path = "EventQueue.sampleValuesChecked" },
        .{
            .path = "EventQueue.selectionString",
            .returns = .{ .ownership = .caller, .release = "EventQueue.freeSelectionString" },
        },
        .{ .path = "EventQueue.freeSelectionString", .params = &.{.{ .name = "value" }} },
        .{ .path = "EventQueue.echoCString", .params = &.{.{ .name = "text" }} },
        .{ .path = "EventQueue.sampleCString" },
        .{
            .path = "EventQueue.extractPaths",
            .params = &.{.{ .name = "paths", .semantic = .utf8_string }},
        },
        .{ .path = "EventQueue.extractSentinelSlices", .params = &.{.{ .name = "paths" }} },
        .{ .path = "EventQueue.extractSentinelPointers", .params = &.{.{ .name = "paths" }} },
        .{
            .path = "EventQueue.extractSamples",
            .returns = .{ .ownership = .caller, .release = "EventQueue.freeSamples" },
        },
        .{
            .path = "EventQueue.extractSamplesChecked",
            .returns = .{ .ownership = .caller, .release = "EventQueue.freeSamples" },
        },
        .{ .path = "EventQueue.freeSamples", .params = &.{.{ .name = "samples" }} },
        .{
            .path = "EventQueue.extractLimits",
            .returns = .{ .ownership = .caller, .release = "EventQueue.freeLimits" },
        },
        .{ .path = "EventQueue.freeLimits", .params = &.{.{ .name = "rows" }} },
        .{ .path = "EventQueue.acceptStats", .params = &.{.{ .name = "values" }} },
        // The `...Into(dst)` shape: the caller owns the buffer, and the result
        // says how much of it was filled.
        .{
            .path = "EventQueue.extractSamplesInto",
            .params = &.{.{ .name = "dst", .direction = .out, .written = .result }},
        },
        .{
            .path = "EventQueue.limitsInto",
            .params = &.{.{ .name = "dst", .direction = .out, .written = .result }},
        },
        .{
            .path = "EventQueue.estimate",
            .params = &.{.{ .name = "output", .direction = .out, .written = .result }},
        },
        .{ .path = "EventQueue.sampleStats" },
        .{ .path = "EventQueue.sampleLimits" },
        .{ .path = "EventQueue.len" },
        .{ .path = "EventQueue.capacity" },
        .{ .path = "EventQueue.policy" },
        .{ .path = "EventQueue.dropped" },
        .{ .path = "EventQueue.processed" },
        .{ .path = "EventQueue.stats" },
        .{ .path = "EventQueue.limits" },
        .{ .path = "EventQueue.applyLimits", .params = &.{.{ .name = "updated" }} },
        .{ .path = "EventQueue.clear" },
        .{ .path = "EventQueue.deinit" },
        // A constructor and destructor declared beside their type rather than
        // inside it, paired by naming the type instead of by their spelling.
        .{ .path = "root.newTicker", .params = &.{.{ .name = "interval" }}, .constructs = library.Ticker },
        .{ .path = "root.freeTicker", .receiver = library.Ticker, .destroys = library.Ticker },
        .{ .path = "root.inspectTicker", .params = &.{ .{ .name = "info" }, .{ .name = "ticker" } } },
        .{ .path = "root.liveTickers" },
        .{ .path = "root.liveStreams" },
        .{ .path = "root.liveQueues" },
        .{ .path = "root.liveSamples" },
        .{ .path = "root.liveLimits" },
        .{ .path = "root.liveSelectionStrings" },
    },
    .methods = &.{
        .{
            .receiver = library.Ticker,
            .strip_prefix = "ticker",
            .functions = &.{
                .{ .path = "root.tickerAdvance", .params = &.{.{ .name = "steps" }} },
                .{ .path = "root.tickerElapsed" },
            },
        },
    },
});
