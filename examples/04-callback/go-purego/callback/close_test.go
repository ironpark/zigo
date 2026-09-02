package callback

import (
	"errors"
	"testing"
	"time"
)

// Close never waits for a call that is inside native, and it never makes a
// third party wait either: a call made while Close is pending is refused at
// once instead of queueing behind it. The callback holds the first Run
// inside native for as long as the test needs.
func TestCloseDoesNotBlockOtherCalls(t *testing.T) {
	entered := make(chan struct{})
	release := make(chan struct{})
	context, err := NewCallbackContext(func(value int32) int32 {
		close(entered)
		<-release
		return value + 1
	})
	if err != nil {
		t.Fatal(err)
	}

	first := make(chan error, 1)
	go func() {
		got, err := context.Run(7)
		if err == nil && got != 8 {
			err = errors.New("Run(7) != 8")
		}
		first <- err
	}()
	<-entered

	closed := make(chan struct{})
	go func() {
		defer close(closed)
		context.Close()
	}()
	select {
	case <-closed:
	case <-time.After(5 * time.Second):
		t.Fatal("Close waited for the call inside native")
	}

	refused := make(chan error, 1)
	go func() {
		_, err := context.Run(7)
		refused <- err
	}()
	select {
	case err := <-refused:
		if !errors.Is(err, ErrInvalidHandle) {
			t.Fatalf("Run after Close = %#v, want *HandleError", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("a call after Close queued behind the call inside native")
	}

	close(release)
	if err := <-first; err != nil {
		t.Fatalf("the call inside native during Close failed: %v", err)
	}
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("active callback handles = %d, want 0", got)
	}
}
