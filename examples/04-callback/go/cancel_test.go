package callback

import (
	"context"
	"sync/atomic"
	"testing"
)

func TestCallbackPanicTripsCancel(t *testing.T) {
	var calls atomic.Int32
	expectCallbackPanic(t, "ApplyUntilCancelled", "stop", func() {
		_, _ = ApplyUntilCancelled(context.Background(), 1_000_000, func(int32) (int32, error) {
			calls.Add(1)
			panic("stop")
		})
	})
	if got := calls.Load(); got != 1 {
		t.Fatalf("callback calls = %d, want 1", got)
	}
}
