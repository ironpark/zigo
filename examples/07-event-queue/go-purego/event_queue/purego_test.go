package event_queue

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	eventtypes "example.com/zigo/event-queue-purego/event_queue/types"
	"time"
)

// installDir is the directory `zig build go-lib` installs the shared library
// into. Zig puts a DLL next to the executables and everything else in lib.
func installDir() string {
	if runtime.GOOS == "windows" {
		return "bin"
	}
	return "lib"
}

// A generated handle closes like any other Go resource.
var _ io.Closer = (*EventQueue)(nil)

// must unwraps a generated call whose only failure mode here would be a nil or
// closed handle.
func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

func init() {
	// An explicit path keeps the test independent of the loader search path;
	// ZIGO_LIBRARY_PATH still wins so the artifact can be installed elsewhere.
	_, file, _, _ := runtime.Caller(0)
	path := os.Getenv("ZIGO_LIBRARY_PATH")
	if path == "" {
		path = filepath.Join(filepath.Dir(file), "..", "..", "zig-out", installDir(), DefaultLibraryName)
	}
	if err := LoadLibrary(path); err != nil {
		panic(err)
	}
}

func TestPuregoRetainedRollbackCloseAndPanic(t *testing.T) {
	observer := func(uint64, int32) int32 { return 0 }
	if _, err := NewEventQueue("", 1, PolicyReject, observer); !errors.Is(err, ErrInvalidName) {
		t.Fatalf("constructor rollback error = %v", err)
	}
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("handles after rollback = %d", got)
	}

	queue, err := NewEventQueue("events", 2, PolicyReject, func(uint64, int32) int32 { panic("observer") })
	if err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue(1, 10); err != nil {
		t.Fatal(err)
	}
	expectCallbackPanic(t, "EventQueue.Process", "observer", func() { _, _ = queue.Process(1) })
	queue.Close()
	queue.Close()
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("handles after Close = %d", got)
	}
	if got := callbackDispatcherCount(); got != 1 {
		t.Fatalf("dispatchers = %d, want 1", got)
	}
}

func TestPuregoNumericSliceReturnIsCopied(t *testing.T) {
	queue, err := NewEventQueue("samples", 2, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()

	first := must(queue.SampleValues())
	first[0] = 99
	second := must(queue.SampleValues())
	if second[0] != 0.25 {
		t.Fatalf("SampleValues() aliased native memory: second[0] = %v", second[0])
	}
}

func TestPuregoOpenEnumRoundTrip(t *testing.T) {
	unknown := eventtypes.QueueSignal(77)
	if got := EchoQueueSignal(unknown); got != unknown {
		t.Fatalf("EchoQueueSignal(77) = %d, want 77", got)
	}
	if got := unknown.String(); got != "QueueSignal(77)" {
		t.Fatalf("QueueSignal(77).String() = %q, want %q", got, "QueueSignal(77)")
	}
}

// Clone is not named like a constructor; only its `.returns = .caller`
// metadata makes it hand over an owned handle that carries its own retained
// observer.
func TestPuregoCloneOwnsItsObserverHandle(t *testing.T) {
	queue, err := NewEventQueue("source", 2, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue(1, 10); err != nil {
		t.Fatal(err)
	}

	copied, err := queue.Clone(func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	if got := LiveQueues(); got != 2 {
		t.Fatalf("LiveQueues() = %d, want 2", got)
	}
	if got := activeCallbackHandleCount(); got != 2 {
		t.Fatalf("handles after Clone = %d, want 2", got)
	}
	if got, err := copied.Process(1); err != nil || got != 1 {
		t.Fatalf("clone Process(1) = (%d, %v), want (1, nil)", got, err)
	}

	copied.Close()
	if got := LiveQueues(); got != 1 {
		t.Fatalf("LiveQueues() after clone Close = %d, want 1", got)
	}
	if got := activeCallbackHandleCount(); got != 1 {
		t.Fatalf("handles after clone Close = %d, want 1", got)
	}
	queue.Close()
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("handles after Close = %d, want 0", got)
	}
}

// The Zig parameter is `?*const EventQueue`, so a nil handle crosses as NULL
// rather than becoming a *HandleError.
func TestPuregoMergeFromAcceptsANilOptionalHandle(t *testing.T) {
	observer := func(uint64, int32) int32 { return 0 }
	target, err := NewEventQueue("target", 4, PolicyReject, observer)
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	source, err := NewEventQueue("source", 4, PolicyReject, observer)
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	if err := source.Enqueue(1, 10); err != nil {
		t.Fatal(err)
	}

	if got, err := target.MergeFrom(nil); err != nil || got != 0 {
		t.Fatalf("MergeFrom(nil) = (%d, %v), want (0, nil)", got, err)
	}
	if got, err := target.MergeFrom(source); err != nil || got != 1 {
		t.Fatalf("MergeFrom(source) = (%d, %v), want (1, nil)", got, err)
	}
}

func TestPuregoAutomaticCleanup(t *testing.T) {
	func() {
		queue, err := NewEventQueue("cleanup", 1, PolicyReject, func(uint64, int32) int32 { return 0 })
		if err != nil {
			t.Fatal(err)
		}
		_ = queue
	}()
	deadline := time.Now().Add(5 * time.Second)
	for (activeCallbackHandleCount() != 0 || LiveQueues() != 0) && time.Now().Before(deadline) {
		runtime.GC()
		time.Sleep(10 * time.Millisecond)
	}
	if activeCallbackHandleCount() != 0 || LiveQueues() != 0 {
		t.Fatalf("automatic cleanup leaked: callbacks=%d queues=%d", activeCallbackHandleCount(), LiveQueues())
	}
}

// expectCallbackPanic runs call and requires it to panic with the
// *CallbackPanicError the binding rethrows for a Go callback panic. It
// returns the error for further inspection.
func expectCallbackPanic(t *testing.T, operation string, value any, call func()) *CallbackPanicError {
	t.Helper()
	var recovered any
	func() {
		defer func() { recovered = recover() }()
		call()
	}()
	err, ok := recovered.(error)
	if !ok {
		t.Fatalf("recovered %v (%T), want *CallbackPanicError", recovered, recovered)
	}
	var panicErr *CallbackPanicError
	if !errors.As(err, &panicErr) {
		t.Fatalf("recovered %v, want *CallbackPanicError", err)
	}
	if !errors.Is(err, ErrCallbackPanic) {
		t.Fatalf("errors.Is(%v, ErrCallbackPanic) = false", err)
	}
	if panicErr.Operation != operation {
		t.Fatalf("Operation = %q, want %q", panicErr.Operation, operation)
	}
	if panicErr.Value != value {
		t.Fatalf("Value = %v, want %v", panicErr.Value, value)
	}
	if len(panicErr.Stack) == 0 {
		t.Fatal("Stack is empty")
	}
	return panicErr
}
