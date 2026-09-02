package callback

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
)

// installDir is the directory `zig build go-lib` installs the shared library
// into. Zig puts a DLL next to the executables and everything else in lib.
func installDir() string {
	if runtime.GOOS == "windows" {
		return "bin"
	}
	return "lib"
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
	got, err := context.Run(9)
	if err != nil {
		t.Fatal(err)
	}
	if got != 18 {
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
	expectCallbackPanic(t, "CallbackContext.Run", "boom", func() { _, _ = panicking.Run(1) })
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
	go func() { defer wait.Done(); _, _ = context.Run(7) }()
	<-entered
	go func() { defer wait.Done(); context.Close() }()
	close(release)
	wait.Wait()
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("callback handles after concurrent Close = %d", got)
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
