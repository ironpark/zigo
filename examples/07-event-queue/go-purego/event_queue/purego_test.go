package event_queue

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func init() {
	// An explicit path keeps the test independent of the loader search path;
	// ZIGO_LIBRARY_PATH still wins so the artifact can be installed elsewhere.
	_, file, _, _ := runtime.Caller(0)
	path := os.Getenv("ZIGO_LIBRARY_PATH")
	if path == "" {
		path = filepath.Join(filepath.Dir(file), "..", "..", "zig-out", "lib", DefaultLibraryName)
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
	if _, err := queue.Process(1); !errors.Is(err, ErrObserverPanicked) {
		t.Fatalf("panic translation = %v", err)
	}
	queue.Close()
	queue.Close()
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("handles after Close = %d", got)
	}
	if got := callbackDispatcherCount(); got != 1 {
		t.Fatalf("dispatchers = %d, want 1", got)
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
