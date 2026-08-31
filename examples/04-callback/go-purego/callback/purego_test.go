package callback

import (
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
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

func TestBorrowedAndRetainedCallbacks(t *testing.T) {
	for i := int32(0); i < 500; i++ {
		if got := Apply(i, func(value int32) int32 { return value + 1 }); got != i+1 {
			t.Fatalf("Apply(%d) = %d", i, got)
		}
		if got := activeCallbackHandleCount(); got != 0 {
			t.Fatalf("borrowed callback handles = %d, want 0", got)
		}
	}
	context, err := NewCallbackContext(func(value int32) int32 { return value * 2 })
	if err != nil {
		t.Fatal(err)
	}
	if got := context.Run(9); got != 18 {
		t.Fatalf("Run(9) = %d, want 18", got)
	}
	context.Close()
	context.Close()
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("retained callback handles = %d, want 0", got)
	}
	if got := callbackDispatcherCount(); got != 1 {
		t.Fatalf("permanent callback dispatchers = %d, want one unique signature", got)
	}
}

func TestCallbackPanicAndConcurrentClose(t *testing.T) {
	panicking, err := NewCallbackContext(func(int32) int32 { panic("boom") })
	if err != nil {
		t.Fatal(err)
	}
	if got := panicking.Run(1); got != -3 {
		t.Fatalf("panicking callback = %d, want -3", got)
	}
	panicking.Close()

	entered := make(chan struct{})
	release := make(chan struct{})
	context, err := NewCallbackContext(func(value int32) int32 {
		close(entered)
		<-release
		return value
	})
	if err != nil {
		t.Fatal(err)
	}
	var wait sync.WaitGroup
	wait.Add(2)
	go func() { defer wait.Done(); _ = context.Run(7) }()
	<-entered
	go func() { defer wait.Done(); context.Close() }()
	close(release)
	wait.Wait()
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("callback handles after concurrent Close = %d", got)
	}
}
