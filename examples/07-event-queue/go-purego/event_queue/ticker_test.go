package event_queue

import (
	"errors"
	"testing"

	eventtypes "example.com/zigo/event-queue-purego/event_queue/types"
)

// `newTicker` and `freeTicker` are free functions beside `Ticker` rather than
// methods on it, and the binding paired them with `.constructs`/`.destroys`.
// The Go surface has to be the same one a method pair produces: a constructor
// named after the type, and a `Close` that ends the handle's life.
func TestPairedFreeFunctionsBecomeAConstructorAndClose(t *testing.T) {
	ticker, err := eventtypes.NewTicker(4)
	if err != nil {
		t.Fatal(err)
	}
	elapsed, err := ticker.Advance(3)
	if err != nil {
		t.Fatal(err)
	}
	if elapsed != 0 {
		t.Fatalf("elapsed = %d, want 0", elapsed)
	}
	if raw, err := ticker.Elapsed(); err != nil || raw != 3 {
		t.Fatalf("Elapsed() = (%d, %v), want (3, nil)", raw, err)
	}
	if elapsed, err = ticker.Advance(5); err != nil {
		t.Fatal(err)
	} else if elapsed != 2 {
		t.Fatalf("elapsed = %d, want 2", elapsed)
	}
	live := eventtypes.LiveTickers()
	if live != 1 {
		t.Fatalf("live tickers = %d, want 1", live)
	}
	if err := ticker.Close(); err != nil {
		t.Fatal(err)
	}
	if live = eventtypes.LiveTickers(); live != 0 {
		t.Fatalf("live tickers after Close = %d, want 0", live)
	}
	var handleErr *eventtypes.HandleError
	if _, err := ticker.Advance(1); !errors.As(err, &handleErr) {
		t.Fatalf("Advance after Close = %v, want a HandleError", err)
	}
}

func TestPairedConstructorReportsItsError(t *testing.T) {
	if _, err := eventtypes.NewTicker(0); !errors.Is(err, eventtypes.ErrInvalidInterval) {
		t.Fatalf("NewTicker(0) = %v, want ErrInvalidInterval", err)
	}
}
