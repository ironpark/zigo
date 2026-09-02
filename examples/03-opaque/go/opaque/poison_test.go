package opaque

import (
	"errors"
	"strings"
	"testing"
)

// A Zig panic longjmps out of the native frames without running their defers,
// so whatever the handle points at may be half-changed. The call reports the
// panic once; every later call on that handle is refused with the same kind
// of error, and Close leaks the native object rather than release it.
func TestPanicPoisonsTheHandle(t *testing.T) {
	context, err := NewContext()
	if err != nil {
		t.Fatal(err)
	}
	live := LiveBytes()

	err = context.Crash()
	if !errors.Is(err, ErrNativePanic) {
		t.Fatalf("Crash() = %#v, want *NativePanicError", err)
	}
	if !strings.Contains(err.Error(), "deliberate handle panic") {
		t.Fatalf("Crash() = %q, want the panic message", err)
	}

	_, err = context.Add(1)
	if !errors.Is(err, ErrNativePanic) {
		t.Fatalf("Add(1) after a panic = %#v, want *NativePanicError", err)
	}
	var refused *NativePanicError
	if !errors.As(err, &refused) || refused.Operation != "Context.Add receiver" {
		t.Fatalf("Add(1) after a panic = %#v, want the refused operation named", err)
	}
	if !strings.Contains(refused.Message, "Context.Crash") || !strings.Contains(refused.Message, "deliberate handle panic") {
		t.Fatalf("Add(1) after a panic = %q, want the earlier panic named", err)
	}

	if err := context.Close(); err != nil {
		t.Fatal(err)
	}
	if got := LiveBytes(); got != live {
		t.Fatalf("LiveBytes() after closing a poisoned handle = %d, want %d (leaked on purpose)", got, live)
	}
	if _, err := context.Add(1); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Add(1) after Close = %#v, want *HandleError", err)
	}
}
