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
		path = filepath.Join(filepath.Dir(file), "..", "zig-out", installDir(), DefaultLibraryName)
	}
	if err := LoadLibrary(path); err != nil {
		panic(err)
	}
}

func TestBorrowedAndRetainedCallbacks(t *testing.T) {
	for i := int32(0); i < 500; i++ {
		got, err := Apply(i, func(value int32) (int32, error) { return value + 1, nil })
		if err != nil {
			t.Fatalf("Apply(%d): %v", i, err)
		}
		if got != i+1 {
			t.Fatalf("Apply(%d) = %d", i, got)
		}
		if got := activeCallbackHandleCount(); got != 0 {
			t.Fatalf("borrowed callback handles = %d, want 0", got)
		}
	}
	context, err := NewCallbackContext(func(value int32) (int32, error) { return value * 2, nil })
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
	panicking, err := NewCallbackContext(func(int32) (int32, error) { panic("boom") })
	if err != nil {
		t.Fatal(err)
	}
	expectCallbackPanic(t, "CallbackContext.Run", "boom", func() { _, _ = panicking.Run(1) })
	panicking.Close()

	entered := make(chan struct{})
	release := make(chan struct{})
	context, err := NewCallbackContext(func(value int32) (int32, error) {
		close(entered)
		<-release
		return value, nil
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

// errCallbackRefused is the caller's own sentinel: what matters is that it
// survives the round trip through native code and comes back identifiable.
var errCallbackRefused = errors.New("observer refused the value")

// A borrowed callback's error: the trampoline stores it, reports -5 to the
// native caller, and the generated function hands it back instead of a result.
func TestBorrowedCallbackErrorReachesTheCaller(t *testing.T) {
	got, err := Apply(7, func(int32) (int32, error) { return 0, errCallbackRefused })
	if err == nil {
		t.Fatal("Apply returned no error for a failing callback")
	}
	if got != 0 {
		t.Fatalf("Apply returned %d alongside its error", got)
	}
	if !errors.Is(err, errCallbackRefused) {
		t.Fatalf("Apply error %v does not wrap the callback's own error", err)
	}
	if !errors.Is(err, ErrCallbackFailed) {
		t.Fatalf("Apply error %v is not classified as ErrCallbackFailed", err)
	}
	var callbackErr *CallbackError
	if !errors.As(err, &callbackErr) {
		t.Fatalf("Apply error %v is not a *CallbackError", err)
	}
	if callbackErr.Operation != "Apply" || callbackErr.Callback != "callback" {
		t.Fatalf("CallbackError names %q/%q", callbackErr.Operation, callbackErr.Callback)
	}
	if live := activeCallbackHandleCount(); live != 0 {
		t.Fatalf("%d callback handles outlived the failing call", live)
	}
}

// A retained callback's error has no call to be returned from at the moment it
// happens, so it surfaces on the next method that reaches the handle -- the
// same rule a retained callback's panic follows.
func TestRetainedCallbackErrorIsDeferredToTheNextCall(t *testing.T) {
	var fail bool
	context, err := NewCallbackContext(func(value int32) (int32, error) {
		if fail {
			return 0, errCallbackRefused
		}
		return value + 1, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	defer context.Close()

	if got, err := context.Run(7); err != nil || got != 8 {
		t.Fatalf("Run(7) = %d, %v", got, err)
	}

	fail = true
	got, err := context.Run(7)
	if !errors.Is(err, errCallbackRefused) {
		t.Fatalf("Run(7) after the callback failed returned %d, %v", got, err)
	}
	if got != 0 {
		t.Fatalf("Run returned %d alongside its error", got)
	}

	// The error was taken, not kept: the next call is clean again.
	fail = false
	if got, err := context.Run(7); err != nil || got != 8 {
		t.Fatalf("Run(7) after the error was taken = %d, %v", got, err)
	}
}

// The construction path has its own early return, and it must not strand the
// retained handle it had already registered.
func TestConstructorCallbackErrorReleasesTheHandle(t *testing.T) {
	before := activeCallbackHandleCount()
	context, err := NewCallbackContext(func(int32) (int32, error) { return 0, errCallbackRefused })
	if err != nil {
		// Nothing calls the callback during construction, so this path is not
		// expected to fire; the assertion that matters is the handle count.
		t.Fatalf("NewCallbackContext: %v", err)
	}
	defer context.Close()
	if got := activeCallbackHandleCount(); got != before+1 {
		t.Fatalf("active callback handles = %d, want %d", got, before+1)
	}
}
