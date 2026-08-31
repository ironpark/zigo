package callback

import (
	"errors"
	"strings"
	"testing"
)

var _ CallbackContextCallback = func(int32) int32 { return 0 }

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
		context, err := NewCallbackContext(func(value int32) int32 { return value + 1 })
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
		if got := Apply(value, func(input int32) int32 { return input + 1 }); got != value+1 {
			t.Fatalf("Apply(%d) = %d", value, got)
		}
	}
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("active callback handles = %d, want 0", got)
	}
}

func TestCallbackPanicIsContained(t *testing.T) {
	context, err := NewCallbackContext(func(int32) int32 { panic("boom") })
	if err != nil {
		t.Fatal(err)
	}
	defer context.Close()
	got, err := context.Run(1)
	if err != nil {
		t.Fatal(err)
	}
	if got != -3 {
		t.Fatalf("Run() = %d, want -3", got)
	}
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
