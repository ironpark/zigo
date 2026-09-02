package event_queue

import (
	"errors"
	"testing"
)

func TestMethodConstructorOwnsReturnedHandle(t *testing.T) {
	queue, err := NewEventQueue("method constructor", 7, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()

	stream, err := queue.NewStream()
	if err != nil {
		t.Fatal(err)
	}
	if capacity, err := stream.Capacity(); err != nil {
		t.Fatal(err)
	} else if capacity != 7 {
		t.Fatalf("capacity = %d, want 7", capacity)
	}
	if live := LiveStreams(); live != 1 {
		t.Fatalf("live streams = %d, want 1", live)
	}
	if err := queue.Close(); !errors.Is(err, ErrHandleInUse) {
		t.Fatalf("queue Close with open stream = %v, want ErrHandleInUse", err)
	} else {
		var inUse *HandleInUseError
		if !errors.As(err, &inUse) || inUse.Children != 1 {
			t.Fatalf("queue Close error = %#v, want HandleInUseError with one child", err)
		}
	}
	if capacity, err := stream.Capacity(); err != nil || capacity != 7 {
		t.Fatalf("stream after refused parent Close = (%d, %v), want (7, nil)", capacity, err)
	}
	if err := stream.Close(); err != nil {
		t.Fatal(err)
	}
	if err := queue.Close(); err != nil {
		t.Fatalf("queue Close after stream Close = %v", err)
	}
	if live := LiveStreams(); live != 0 {
		t.Fatalf("live streams after Close = %d, want 0", live)
	}
	var handleErr *HandleError
	if _, err := stream.Capacity(); !errors.As(err, &handleErr) {
		t.Fatalf("Capacity after Close = %v, want a HandleError", err)
	}
}

func TestMethodConstructorChecksReceiver(t *testing.T) {
	var queue *EventQueue
	if _, err := queue.NewStream(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("nil queue NewStream = %v, want ErrInvalidHandle", err)
	}
}
