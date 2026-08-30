package callback

import (
	"errors"
	"strings"
	"testing"
)

func TestGenericSpecializations(t *testing.T) {
	floatBuffer, err := NewFloatBuffer()
	if err != nil {
		t.Fatal(err)
	}
	defer floatBuffer.Close()
	floatBuffer.Push(1.5)
	if got := floatBuffer.Len(); got != 1 {
		t.Fatalf("FloatBuffer.Len() = %d, want 1", got)
	}

	intBuffer, err := NewIntBuffer()
	if err != nil {
		t.Fatal(err)
	}
	defer intBuffer.Close()
	intBuffer.Push(7)
	if got := intBuffer.Len(); got != 1 {
		t.Fatalf("IntBuffer.Len() = %d, want 1", got)
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
		if got := context.Run(7); got != 8 {
			t.Fatalf("Run() = %d, want 8", got)
		}
		context.Close()
		context.Close()
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
	if got := context.Run(1); got != -3 {
		t.Fatalf("Run() = %d, want -3", got)
	}
}

func TestZigPanicIsDiagnosable(t *testing.T) {
	err := PanicNow()
	var zigoErr *Error
	if !errors.As(err, &zigoErr) {
		t.Fatalf("PanicNow() error = %T, want *Error", err)
	}
	if zigoErr.Code != -2 {
		t.Fatalf("PanicNow() code = %d, want -2", zigoErr.Code)
	}
	if !strings.Contains(zigoErr.Error(), "deliberate boundary panic") {
		t.Fatalf("PanicNow() error = %q", zigoErr.Error())
	}
}
