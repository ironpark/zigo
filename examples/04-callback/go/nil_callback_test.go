package callback

import (
	"errors"
	"testing"
)

func TestNilBorrowedCallbackRejectedBeforeAllocation(t *testing.T) {
	before := zigoActiveCallbackHandleCount()
	if _, err := Apply(1, nil); !errors.Is(err, ErrNilCallback) {
		t.Fatalf("Apply nil = %v", err)
	}
	defer func() {
		recovered := recover()
		err, ok := recovered.(error)
		if !ok || !errors.Is(err, ErrNilCallback) {
			t.Fatalf("Notify nil panic = %v", recovered)
		}
		if got := zigoActiveCallbackHandleCount(); got != before {
			t.Fatalf("nil callback leaked handles: %d -> %d", before, got)
		}
	}()
	Notify(1, nil)
}
