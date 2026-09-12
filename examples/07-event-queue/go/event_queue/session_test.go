package event_queue

import (
	"errors"
	"sync"
	"testing"
)

func newSessionQueue(t *testing.T, label string) *EventQueue {
	t.Helper()
	queue, err := NewEventQueue(label, 4, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	return queue
}

// A session closes what it adopted in the order the native side insists on:
// children first, then the primary. The same handles closed by hand in the
// other order are refused, which is the contrast the session exists for.
func TestSessionClosesChildrenBeforePrimary(t *testing.T) {
	queue := newSessionQueue(t, "session order")
	stream, err := queue.NewStream()
	if err != nil {
		t.Fatal(err)
	}
	if err := queue.Close(); !errors.Is(err, ErrHandleInUse) {
		t.Fatalf("queue Close with an open stream = %v, want ErrHandleInUse", err)
	}

	session := NewSession(queue).AddStream(stream)
	if got := session.EventQueue(); got != queue {
		t.Fatalf("EventQueue() = %p, want %p", got, queue)
	}
	if got := session.Streams(); len(got) != 1 || got[0] != stream {
		t.Fatalf("Streams() = %v, want [%p]", got, stream)
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

// A primary hands out as many children as the caller asks for, so a session
// adopts a list rather than one handle per type.
func TestSessionAdoptsEveryChild(t *testing.T) {
	queue := newSessionQueue(t, "session many")
	session := NewSession(queue)
	streams := make([]*Stream, 3)
	for index := range streams {
		stream, err := queue.NewStream()
		if err != nil {
			t.Fatal(err)
		}
		streams[index] = stream
		session.AddStream(stream)
	}
	if live := LiveStreams(); live != 3 {
		t.Fatalf("live streams before Close = %d, want 3", live)
	}
	adopted := session.Streams()
	if len(adopted) != 3 {
		t.Fatalf("Streams() = %d handles, want 3", len(adopted))
	}
	for index, stream := range adopted {
		if stream != streams[index] {
			t.Fatalf("Streams()[%d] = %p, want %p (oldest first)", index, stream, streams[index])
		}
	}
	// The returned slice is a copy: mutating it must not reach the session.
	adopted[0] = nil
	if again := session.Streams(); again[0] != streams[0] {
		t.Fatal("Streams() handed out the session's own slice")
	}
	if err := session.Close(); err != nil {
		t.Fatalf("session Close = %v, want nil", err)
	}
	if live := LiveStreams(); live != 0 {
		t.Fatalf("live streams after Close = %d, want 0", live)
	}
}

// A member that fails to close does not stop the others, and the failure is
// reported. A stream the session never adopted keeps the queue open, so the
// primary is exactly that member.
func TestSessionReportsAPartialFailure(t *testing.T) {
	queue := newSessionQueue(t, "session partial")
	adopted, err := queue.NewStream()
	if err != nil {
		t.Fatal(err)
	}
	loose, err := queue.NewStream()
	if err != nil {
		t.Fatal(err)
	}

	closeErr := NewSession(queue).AddStream(adopted).Close()
	if !errors.Is(closeErr, ErrHandleInUse) {
		t.Fatalf("session Close with a loose child = %v, want ErrHandleInUse", closeErr)
	}
	// The adopted child was closed even though the primary after it failed.
	if live := LiveStreams(); live != 1 {
		t.Fatalf("live streams after the failed Close = %d, want 1 (the loose one)", live)
	}
	if live := LiveQueues(); live != 1 {
		t.Fatalf("live queues after the failed Close = %d, want 1", live)
	}

	if err := loose.Close(); err != nil {
		t.Fatal(err)
	}
	if err := queue.Close(); err != nil {
		t.Fatal(err)
	}
}

// Close is idempotent and safe to call from several goroutines at once: every
// caller gets the first result.
func TestSessionCloseIsIdempotent(t *testing.T) {
	queue := newSessionQueue(t, "session once")
	stream, err := queue.NewStream()
	if err != nil {
		t.Fatal(err)
	}
	session := NewSession(queue).AddStream(stream)

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

// A nil handle is ignored, so a conditional path that never created a child
// needs no guard at the call site.
func TestSessionSkipsNilChildren(t *testing.T) {
	queue := newSessionQueue(t, "session nil child")
	session := NewSession(queue).AddStream(nil)
	if got := session.Streams(); len(got) != 0 {
		t.Fatalf("Streams() = %v, want none", got)
	}
	if err := session.Close(); err != nil {
		t.Fatalf("session Close with no children = %v, want nil", err)
	}
	if err := session.Close(); err != nil {
		t.Fatalf("second session Close = %v, want the first result (nil)", err)
	}
	if live := LiveQueues(); live != 0 {
		t.Fatalf("live queues after Close = %d, want 0", live)
	}
}

// Adopting after Close has run is a caller mistake, but the handle must not
// leak: the session closes it on the spot.
func TestSessionClosesHandlesAdoptedAfterClose(t *testing.T) {
	queue := newSessionQueue(t, "session late adopt")
	stream, err := queue.NewStream()
	if err != nil {
		t.Fatal(err)
	}
	session := NewSession(queue)
	if err := session.Close(); !errors.Is(err, ErrHandleInUse) {
		t.Fatalf("Close with an unadopted child = %v, want ErrHandleInUse", err)
	}

	session.AddStream(stream)
	if live := LiveStreams(); live != 0 {
		t.Fatalf("live streams after a late adopt = %d, want 0", live)
	}
	if got := session.Streams(); len(got) != 0 {
		t.Fatalf("Streams() after a late adopt = %v, want none", got)
	}
	if err := queue.Close(); err != nil {
		t.Fatal(err)
	}
}

// The session implements io.Closer, which the generated file asserts at compile
// time; this checks the method set a caller actually sees agrees.
func TestSessionIsACloser(t *testing.T) {
	queue := newSessionQueue(t, "session closer")
	var closer interface{ Close() error } = NewSession(queue)
	if err := closer.Close(); err != nil {
		t.Fatalf("Close through the interface = %v, want nil", err)
	}
}
