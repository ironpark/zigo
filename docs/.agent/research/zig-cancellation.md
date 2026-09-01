# Zig 0.16+ In-Flight Cancellation — Research for zigo's ctx-cancel Convention

Date: 2026-09-01. zigo targets **minimum Zig 0.16.0** (`.minimum_zig_version = "0.16.0"` in `build.zig.zon`). Zig master is currently `0.17.0-dev` (ziglang.org/download/index.json, 2026-08-31). Note: Zig's canonical repo moved to Codeberg; the GitHub mirror has no `0.16.0` tag (raw fetch 404s), so 0.16.0 sources below are cited from `codeberg.org/ziglang/zig/raw/tag/0.16.0/`.

## TL;DR — "execute then cancel" in Zig 0.16

- Zig 0.16 shipped the new `std.Io` interface: `io.async(fn, args)` returns a `Future(T)`; `future.cancel(io)` is "await + request cancellation"; cancellation is **cooperative** and surfaces as `error.Canceled` at the task's next *cancellation point* (any `Io` call that has `error.Canceled` in its error set, or an explicit `io.checkCancel()`).
- `Io.Threaded` (the production backend) *can* interrupt in-flight blocking syscalls: it sets an atomic flag then signals the thread (SIGIO on POSIX, `NtCancelSynchronousIoFile`/`NtCancelIoFileEx` on Windows) in a loop until acknowledged.
- All of this requires an `Io` instance and a task spawned *by that Io* — it is per-task machinery, `cancel`/`await` are **not threadsafe**, and cancellation from foreign (C/Go) threads is explicitly unsupported today.
- There is **no std-blessed cancellation-token type** for plain synchronous code; the ecosystem rolls its own `std.atomic.Value(bool)` / token structs.
- For zigo's C-ABI exports called from Go, an atomic-flag token polled by Zig (optionally bridged into `std.Io` via `checkCancel`-style polling on the Zig side) is the only realistic shape; couple to that, not to `std.Io`'s still-churning surface.

## 1. The std.Io cancellation API surface (0.16.0, verified against source)

From `lib/std/Io.zig` at tag 0.16.0:

- `pub const Cancelable = error{ Canceled };` — "Caller has requested the async operation to stop."
- `io.async(function, args) Future(R)` — may run inline (blocking Io) or concurrently; `io.concurrent(...)` guarantees concurrency or fails with `error.ConcurrencyUnavailable`.
- `Future(R).await(io) R` and `Future(R).cancel(io) R` — cancel is documented as: "Equivalent to `await` but places a cancelation request. This causes the task to receive `error.Canceled` from its next 'cancelation point' (if any). A cancelation point is a call to a function in `Io` which can return `error.Canceled`. … only the next cancelation point in that task will return `error.Canceled`: future points will not re-signal … **Idempotent. Not threadsafe.**"
- `Io.Group` — set of tasks awaited/canceled as a whole: `group.async`, `group.concurrent`, `group.await(io) Cancelable!void`, `group.cancel(io)`. A task returning `error.Canceled` into a group is swallowed ("cancelation propagation boundary").
- `io.checkCancel(io) Cancelable!void` — "acts as a pure cancelation point … primary use case is in long-running CPU-bound tasks."
- `io.cancelRequested(io) bool` (master; polling without erroring).
- `io.recancel(io)` — re-arms a consumed cancellation request.
- `CancelProtection` (`.unblocked`/`.blocked`) + `io.swapCancelProtection(new)` — masks cancellation points around critical regions (documented pattern: swap to `.blocked`, `defer` swap back, treat `error.Canceled` as `unreachable`).
- `Io.Select` / `io.select` — wait on multiple futures; `select.cancel()` cancels remaining tasks. Community-recommended way to combine "work" with an external "stop" event, since you cannot cancel a future you are currently awaiting (panics in `Threaded`; "you cannot both await and cancel a future" — kristoff on ziggit #15466; "cancel and await are not thread safe. You can only call them from one thread" — lalinsky).

Canonical usage sketch (kristoff.it / release notes):

```zig
var t = io.async(work, .{args});
defer if (t.cancel(io)) |res| res.deinit() else |_| {};
const result = try t.await(io);
```

Semantics summary: cancellation is **request-based and cooperative** ("When cancelation is requested, the request may or may not be acknowledged" — 0.16.0 release notes). CPU-bound loops must poll (`checkCancel`); I/O-bound code gets cancellation points for free from every cancelable `Io` call.

### Backends and in-flight blocking syscalls

- `Io.Threaded` — "feature-complete, production-ready" per 0.16.0 release notes. Cancellation protocol (matklad's "Zig's Io.Threaded is Neat" + `Threaded.zig` source): canceller sets a shared atomic flag, then signals the target thread in a loop until acknowledged; the signal makes the blocked syscall return `EINTR`; `beginSyscall`/`endSyscall` bracket every syscall and convert acknowledged cancellation into `error.Canceled`; un-canceled `EINTR` retries the syscall (a `robust_cancel` option tunes this — Codeberg PR #30033 "std.Io.Threaded: rework cancellation"). On Windows: `NtCancelSynchronousIoFile` / `NtCancelIoFileEx` (verified in source).
- **Caveat for embedding in a Go process:** `Threaded.init` installs process-global `sigaction` handlers for SIGIO and SIGPIPE (`Threaded.zig` lines ~1607–1716, restored in `deinit`). Inside a Go program this fights the Go runtime's signal handling — a real hazard for zigo-generated bindings that would construct an `Io.Threaded` inside the shared library.
- `Io.Evented` — experimental stackful-coroutine M:N backend; `Io.Uring` — Linux io_uring proof of concept; both explicitly not production-ready in 0.16.0 (release notes).
- Earlier `Threaded` (pre-rework, ziggit #13969) could *not* interrupt mid-syscall; Windows support lagged ("It already works on POSIX systems, but there is additional code that needs to be added to the Windows implementation" — attributed to Andrew Kelley in-thread). The signal-based rework closed most of this gap.

## 2. Cooperative cancellation in plain synchronous Zig

- **No std cancellation-token type exists.** Nothing like Go's `context` or .NET's `CancellationToken` is in std outside the `Io` task machinery.
- Idiomatic pattern is a shared `std.atomic.Value(bool)` (or an enum/int for richer states): worker polls `flag.load(.acquire)` in its loop; canceller does `flag.store(true, .release)`. Ecosystem examples: lithdew's cancellation-token gist (https://gist.github.com/lithdew/2802fa5cb398ccca7d77a899a4b4441f); ziggit "Is there a way to kill/cancel a thread in Zig?" (#5938) — answer: you can't kill, you poll a flag.
- `std.Thread.ResetEvent` serves the inverse direction (wake a *waiter*), useful when the cancellable side blocks on an event rather than looping; it doesn't interrupt syscalls either.
- Inside `std.Io` code, the blessed poll primitive is `io.checkCancel()` / `io.cancelRequested()` — but only for tasks spawned by that Io.

## 3. C-ABI exports (the zigo case)

Can `std.Io` be used inside an `export fn` called from Go? Technically yes as an *internal implementation detail* — `Io.Threaded` is just library code; an exported function (or a library-level init) can create a `Threaded`, get `io()`, and run tasks. But as a **cancellation transport from Go it does not work**:

- `Future.cancel`/`await` are "Idempotent. Not threadsafe" (source doc comments) — a Go goroutine cannot safely call them against a task another thread is awaiting.
- Cancellation must originate from the same Io world. Ziggit #17382 ("Canceling `Threaded` operations from foreign C threads") is exactly this scenario: `Threaded` "ignores signals that weren't initiated from the Zig side as part of canceling, so it'll just restart the syscall if `thread.status.cancelation` hasn't been set." Suggested workarounds were a custom `Io` implementation or plain shared-memory atomics.
- The sigaction-in-`Threaded.init` issue above compounds this inside a Go process.

Real projects: TigerBeetle's `tb_client` C API is completion/callback-based (submit packet, get callback); it does not expose per-request cancellation — teardown is client-close. Ghostty and bun drive long work via their own runtimes/threads rather than exposing cancelable C entry points. I found no real-world Zig library exposing `std.Io` cancellation across a C ABI; flag-polling and "close the handle" are the observed shapes. (Survey via web search; no counterexample found — treat as absence of evidence, not proof.)

### Ranked options for zigo

1. **Recommended — atomic cancel-token parameter, polled.** Generated Zig signature takes an extra `token: ?*const u32` (or `*const bool`; u32 is friendlier for atomics across ABIs and lets 0 = live, 1 = canceled, room for reason codes). Zig side polls `@atomicLoad(u32, token, .acquire) != 0` in loops and/or via a tiny helper, aborts and returns a sentinel/error code that the Go wrapper maps: canceled → `ctx.Err()` (`context.Canceled` or `DeadlineExceeded`, decided on the Go side from ctx state, so Zig needs only one "canceled" code). Go wrapper: allocate the token (C memory or pinned), spawn watcher goroutine `select { <-ctx.Done(): atomic-store 1 }`, call export, stop watcher. Works identically under cgo and purego, no signals, no Io coupling, mirrors what `Io.Threaded` itself does internally (flag + acknowledge).
2. **Token + optional user-supplied `Io` bridging (later).** Inside the Zig function, if the author uses `std.Io`, they can spawn their work in a `Group` and run a small poller task that watches the token and calls `group.cancel(io)` — turning zigo's token into real `error.Canceled` cancellation points, including interrupting blocking syscalls under `Threaded`. This is a Zig-author-side pattern zigo can document, not something the generator must emit.
3. **Callback/event shape** (Go registers a "should-stop" callback Zig invokes): more ABI surface, purego callback limits, no gain over polling.
4. **Handle + separate `cancel(handle)` export** (start returns a job handle; a second export flips the flag): equivalent power to option 1 with more generated API; only worth it if zigo later adds async job submission.
5. **Not viable:** passing Go's ctx into `std.Io` machinery directly, pthread_cancel/thread-kill, or signaling Zig threads from Go (conflicts with both runtimes).

Error-mapping convention suggestion: reserve one status code (e.g. `ZIGO_ERR_CANCELED`) in zigo's existing error-code mapping; Go wrapper returns `ctx.Err()` when that code is seen *and* ctx is done, else surfaces it as a regular error.

## 4. Timeouts and deadlines (0.16.0)

`Io.Timeout` is `union(enum) { none, duration: Clock.Duration, deadline: Clock.Timestamp }` with `Error = error{Timeout}`, converters (`toDeadline`, `toTimestamp`, `toDurationFromNow`) and `Timeout.sleep(io) Cancelable!void` (source, 0.16.0). Type-safe `Clock`/`Duration`/`Timestamp` landed in 0.16 (release notes); timeout-accepting ops (e.g. `netReceive`) take a `Timeout` parameter and can return `error.Timeout` *distinct from* `error.Canceled` — timeout is per-operation, cancellation is per-task; they compose (a canceled task's timed op returns Canceled at the cancellation point). There is no separate `Io.Deadline` type; deadlines are the `.deadline` variant. For zigo: Go's `context.WithTimeout` needs no Zig-side deadline at all — the watcher-goroutine + token approach subsumes it, and Go distinguishes `Canceled` vs `DeadlineExceeded` itself.

## 5. Stability assessment

- 0.14: old async/await keywords long gone; nothing usable.
- 0.15.x: keywords formally removed from the language; new non-generic `Io.Reader`/`Io.Writer` landed; async Io explicitly deferred to 0.16 (0.15.1 release notes).
- 0.16.0: full `std.Io` interface: `async`/`concurrent`/`Future`/`Group`/`Select`/`Batch`, cancellation (`Canceled`, `checkCancel`, `recancel`, `CancelProtection`), `Clock`/`Timeout`. `Threaded` declared production-ready; `Evented`/`Uring` experimental.
- master (0.17-dev): still churning — `Threaded` cancellation rework merged post-0.16 (Codeberg PR #30033, `robust_cancel`), `cancelRequested` present, ongoing ziggit reports of panics/foot-guns around await-vs-cancel (#15466) and foreign-thread cancellation (#17382). Cross-thread cancel semantics, `Evented`, and stackless coroutines are the areas most likely to change.

**Verdict for zigo:** safe to couple to today: the *concepts* (`error.Canceled` as the cancellation value, cooperative flag-poll acknowledgment, one-shot cancel semantics) and a zigo-owned atomic token ABI. Not safe to couple to: `Io` vtable layout, `Threaded` internals, cross-thread `Future.cancel`, or constructing `Io.Threaded` implicitly inside generated bindings (signal-handler conflicts with the Go runtime). The token convention is forward-compatible: if Zig later blesses external cancellation, a token-to-Io bridge can be added without changing the Go-facing API.

## Sources

- Zig 0.16.0 release notes — https://ziglang.org/download/0.16.0/release-notes.html
- Zig 0.15.1 release notes — https://ziglang.org/download/0.15.1/release-notes.html
- `std/Io.zig` @ 0.16.0 — https://codeberg.org/ziglang/zig/raw/tag/0.16.0/lib/std/Io.zig
- `std/Io/Threaded.zig` @ 0.16.0 — https://codeberg.org/ziglang/zig/raw/tag/0.16.0/lib/std/Io/Threaded.zig
- `std/Io.zig` @ master — https://raw.githubusercontent.com/ziglang/zig/master/lib/std/Io.zig
- Loris Cro, "Zig's New Async I/O" — https://kristoff.it/blog/zig-new-async-io/
- matklad, "Zig's Io.Threaded is Neat" (2026-08-06) — https://matklad.github.io/2026/08/06/neat-io-threaded.html
- Codeberg PR #30033, "std.Io.Threaded: rework cancellation" — https://codeberg.org/ziglang/zig/pulls/30033
- Ziggit: "Trying to understand cancellation" — https://ziggit.dev/t/trying-to-understand-cancellation/13969
- Ziggit: "Canceling awaited Future/Group/etc is impossible?" — https://ziggit.dev/t/canceling-awaited-future-group-etc-is-impossible/15466
- Ziggit: "Canceling `Threaded` operations from foreign C threads" — https://ziggit.dev/t/canceling-threaded-operations-from-foreign-c-threads/17382
- Ziggit: "Is there a way to kill/cancel a thread in Zig?" — https://ziggit.dev/t/is-there-a-way-to-kill-cancel-a-thread-in-zig/5938
- lithdew cancellation-token gist — https://gist.github.com/lithdew/2802fa5cb398ccca7d77a899a4b4441f
- Zig download index (version check) — https://ziglang.org/download/index.json

Fetch notes: GitHub mirror lacks the `0.16.0` tag (404 on raw); Codeberg tag used instead. The 0.14.0 release notes were not fetched (0.14 predates the Io work; 0.15.1 notes cover the transition).
