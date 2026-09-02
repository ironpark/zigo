package callback

import (
	"errors"
	"io"
	"strings"
	"testing"
)

// Both callback parameters share the declared Observer type.
var _ Observer = func(int32) (int32, error) { return 0, nil }

// Generated handles close like any other Go resource.
var (
	_ io.Closer = (*FloatBuffer)(nil)
	_ io.Closer = (*IntBuffer)(nil)
	_ io.Closer = (*CallbackContext)(nil)
)

func TestGenericSpecializations(t *testing.T) {
	floatBuffer, err := NewFloatBuffer()
	if err != nil {
		t.Fatal(err)
	}
	defer floatBuffer.Close()
	if err := floatBuffer.Push(1.5); err != nil {
		t.Fatal(err)
	}
	got, err := floatBuffer.Len()
	if err != nil {
		t.Fatal(err)
	}
	if got != 1 {
		t.Fatalf("FloatBuffer.Len() = %d, want 1", got)
	}

	intBuffer, err := NewIntBuffer()
	if err != nil {
		t.Fatal(err)
	}
	defer intBuffer.Close()
	if err := intBuffer.Push(7); err != nil {
		t.Fatal(err)
	}
	length, err := intBuffer.Len()
	if err != nil {
		t.Fatal(err)
	}
	if length != 1 {
		t.Fatalf("IntBuffer.Len() = %d, want 1", length)
	}
}

func TestSystemLibraryLinkIsPropagated(t *testing.T) {
	if got := CompressionBound(1024); got <= 1024 {
		t.Fatalf("CompressionBound(1024) = %d, want > 1024", got)
	}
}

func TestRetainedCallbackLifecycle(t *testing.T) {
	for range 100 {
		context, err := NewCallbackContext(func(value int32) (int32, error) { return value + 1, nil })
		if err != nil {
			t.Fatal(err)
		}
		got, err := context.Run(7)
		if err != nil {
			t.Fatal(err)
		}
		if got != 8 {
			t.Fatalf("Run() = %d, want 8", got)
		}
		context.Close()
		context.Close()
	}
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("active callback handles = %d, want 0", got)
	}
}

func TestBorrowedCallbackLifecycle(t *testing.T) {
	for value := int32(0); value < 100; value++ {
		got, err := Apply(value, func(input int32) (int32, error) { return input + 1, nil })
		if err != nil {
			t.Fatalf("Apply(%d): %v", value, err)
		}
		if got != value+1 {
			t.Fatalf("Apply(%d) = %d", value, got)
		}
	}
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("active callback handles = %d, want 0", got)
	}
}

func TestCallbackPanicIsRethrown(t *testing.T) {
	// The trampoline answers the native caller with -3 so it can unwind, then
	// the generated call resumes the panic on the calling goroutine with the
	// original value attached.
	context, err := NewCallbackContext(func(int32) (int32, error) { panic("boom") })
	if err != nil {
		t.Fatal(err)
	}
	defer context.Close()
	expectCallbackPanic(t, "CallbackContext.Run", "boom", func() { _, _ = context.Run(1) })

	// A borrowed callback rethrows through the plain function too, and the
	// handle it was registered under does not leak.
	expectCallbackPanic(t, "Apply", "borrowed", func() { _, _ = Apply(1, func(int32) (int32, error) { panic("borrowed") }) })
	if got := activeCallbackHandleCount(); got != 1 {
		t.Fatalf("active callback handles = %d, want 1 (the context)", got)
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

func TestZigPanicIsDiagnosable(t *testing.T) {
	// A Zig panic is one event with one sentinel, whichever boundary caught it.
	err := PanicNow()
	if !errors.Is(err, ErrNativePanic) {
		t.Fatalf("errors.Is(%v, ErrNativePanic) = false", err)
	}
	var panicErr *NativePanicError
	if !errors.As(err, &panicErr) {
		t.Fatalf("PanicNow() error = %T, want *NativePanicError", err)
	}
	if !strings.Contains(panicErr.Message, "deliberate boundary panic") {
		t.Fatalf("PanicNow() message = %q", panicErr.Message)
	}
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
