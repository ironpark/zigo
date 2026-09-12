package event_queue

import (
	"errors"
	"sync"
	"testing"
)

// A session closes what it adopted in the order the native side insists on:
// children first, then the primary. The same handles closed by hand in the
// other order are refused, which is the contrast the session exists for.
func TestSessionClosesChildrenBeforePrimary(t *testing.T) {
	queue, err := NewEventQueue("session order", 4, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	stream, err := queue.NewStream()
	if err != nil {
		t.Fatal(err)
	}
	if err := queue.Close(); !errors.Is(err, ErrHandleInUse) {
		t.Fatalf("queue Close with an open stream = %v, want ErrHandleInUse", err)
	}

	session := NewSession(queue, stream)
	if got := session.EventQueue(); got != queue {
		t.Fatalf("EventQueue() = %p, want %p", got, queue)
	}
	if got := session.Stream(); got != stream {
		t.Fatalf("Stream() = %p, want %p", got, stream)
	}
	if err := session.Close(); err != nil {
		t.Fatalf("session Close = %v, want nil", err)
	}
	if live := LiveStreams(); live != 0 {
		t.Fatalf("live streams after session Close = %d, want 0", live)
	}
	if live := LiveQueues(); live != 0 {
		t.Fatalf("live queues after session Close = %d, want 0", live)
	}
	var handleErr *HandleError
	if _, err := stream.Capacity(); !errors.As(err, &handleErr) {
		t.Fatalf("Capacity after session Close = %v, want a HandleError", err)
	}
}

// Close is idempotent and safe to call from several goroutines at once: every
// caller gets the first result.
func TestSessionCloseIsIdempotent(t *testing.T) {
	queue, err := NewEventQueue("session once", 2, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	stream, err := queue.NewStream()
	if err != nil {
		t.Fatal(err)
	}
	session := NewSession(queue, stream)

	const callers = 8
	results := make([]error, callers)
	var group sync.WaitGroup
	for i := range results {
		group.Add(1)
		go func(index int) {
			defer group.Done()
			results[index] = session.Close()
		}(i)
	}
	group.Wait()
	for index, result := range results {
		if result != nil {
			t.Fatalf("concurrent Close[%d] = %v, want nil", index, result)
		}
	}
	if err := session.Close(); err != nil {
		t.Fatalf("Close after the first = %v, want the first result (nil)", err)
	}
	if live := LiveQueues(); live != 0 {
		t.Fatalf("live queues after Close = %d, want 0", live)
	}
}

// A child a conditional path never created is left nil, and the session still
// closes the primary it did adopt.
func TestSessionSkipsNilMembers(t *testing.T) {
	queue, err := NewEventQueue("session nil child", 2, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	session := NewSession(queue, nil)
	if got := session.Stream(); got != nil {
		t.Fatalf("Stream() = %p, want nil", got)
	}
	if err := session.Close(); err != nil {
		t.Fatalf("session Close with a nil child = %v, want nil", err)
	}
	if err := session.Close(); err != nil {
		t.Fatalf("second session Close = %v, want the first result (nil)", err)
	}
	if live := LiveQueues(); live != 0 {
		t.Fatalf("live queues after Close = %d, want 0", live)
	}
}

// The session implements io.Closer, which the generated file asserts at compile
// time; this checks the method set a caller actually sees agrees.
func TestSessionIsACloser(t *testing.T) {
	queue, err := NewEventQueue("session closer", 2, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	var closer interface{ Close() error } = NewSession(queue, nil)
	if err := closer.Close(); err != nil {
		t.Fatalf("Close through the interface = %v, want nil", err)
	}
}
