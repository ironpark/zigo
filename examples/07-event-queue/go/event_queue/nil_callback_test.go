package event_queue

import (
	"errors"
	"testing"
)

func TestNilCallbackRegistrationPreservesOwnership(t *testing.T) {
	before := zigoActiveCallbackHandleCount()
	if queue, err := NewEventQueue("nil", 1, PolicyReject, nil); queue != nil || !errors.Is(err, ErrNilCallback) {
		t.Fatalf("nil constructor = (%v, %v)", queue, err)
	}
	if got := zigoActiveCallbackHandleCount(); got != before {
		t.Fatalf("nil constructor leaked handles: %d -> %d", before, got)
	}
	first, second := 0, 0
	queue, err := NewEventQueue("nil replacement", 1, PolicyReject, func(uint64, int32) int32 { first++; return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()
	checkNil := func() {
		t.Helper()
		active := zigoActiveCallbackHandleCount()
		err := queue.SetObserver(nil)
		var callbackErr *CallbackError
		if !errors.Is(err, ErrNilCallback) || !errors.As(err, &callbackErr) {
			t.Fatalf("nil registration = %v", err)
		}
		if got := zigoActiveCallbackHandleCount(); got != active {
			t.Fatalf("nil registration changed handles: %d -> %d", active, got)
		}
	}
	process := func() {
		t.Helper()
		if err := queue.Enqueue(1, 1); err != nil {
			t.Fatal(err)
		}
		if _, err := queue.Process(1); err != nil {
			t.Fatal(err)
		}
	}
	checkNil()
	process()
	if first != 1 {
		t.Fatalf("original callback calls = %d", first)
	}
	if err := queue.SetObserver(func(uint64, int32) int32 { second++; return 0 }); err != nil {
		t.Fatal(err)
	}
	checkNil()
	process()
	if first != 1 || second != 1 {
		t.Fatalf("replacement callbacks = (%d, %d)", first, second)
	}
	if err := queue.Close(); err != nil {
		t.Fatal(err)
	}
	if got := zigoActiveCallbackHandleCount(); got != before {
		t.Fatalf("Close leaked handles: %d -> %d", before, got)
	}
}
