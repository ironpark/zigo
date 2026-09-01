package tagged_union

import (
	"errors"
	"runtime"
	"sync"
	"testing"
)

// A binding without callbacks gets the same Close serialization as one with
// them. Run this with -race: before every handle carried a mutex, a Close
// racing an in-flight call was a use-after-free.
func TestConcurrentCallsRacingClose(t *testing.T) {
	child, err := NewChild(11)
	if err != nil {
		t.Fatal(err)
	}

	const callers = 8
	var wait sync.WaitGroup
	start := make(chan struct{})
	for range callers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			<-start
			for range 200 {
				got, err := child.Get()
				if err == nil {
					if got != 11 {
						t.Errorf("Get() = %d, want 11", got)
					}
					continue
				}
				var handleErr *HandleError
				if !errors.As(err, &handleErr) {
					t.Errorf("Get() after Close = %#v, want *HandleError", err)
				}
			}
		}()
	}
	wait.Add(1)
	go func() {
		defer wait.Done()
		<-start
		runtime.Gosched()
		child.Close()
	}()
	close(start)
	wait.Wait()

	if _, err := child.Get(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Get after Close = %v, want ErrInvalidHandle", err)
	}
}

// requireOpenOrClosed accepts either a successful projection or the typed
// closed-handle error, and nothing else: a projection racing Close must
// finish cleanly or report the closed handle, never read freed memory.
func requireOpenOrClosed(t *testing.T, what string, err error) {
	t.Helper()
	if err == nil {
		return
	}
	var handleErr *HandleError
	if !errors.As(err, &handleErr) {
		t.Errorf("%s during Close = %#v, want *HandleError", what, err)
	}
}

// Projections and borrowed refs reach their handle through the zigoHandle
// interface, which only exposed the pointer, so they used to run without the
// read lock and a Close racing an in-flight projection was a use-after-free.
// The locker accessor closed that gap; run this with -race.
func TestConcurrentProjectionsRacingClose(t *testing.T) {
	child, err := NewChild(23)
	if err != nil {
		t.Fatal(err)
	}
	defer child.Close()
	value, err := NewValue(7)
	if err != nil {
		t.Fatal(err)
	}
	if err := value.SetChild(child); err != nil {
		t.Fatal(err)
	}
	ref, err := value.Borrow()
	if err != nil {
		t.Fatal(err)
	}
	// A snapshot union reads tag and payload in one native call, so it takes
	// the lock on a different path than the per-variant projections.
	signal, err := NewSignal(5)
	if err != nil {
		t.Fatal(err)
	}

	readers := []struct {
		name string
		read func() error
	}{
		{"Value.Tag", func() error { _, err := value.Tag(); return err }},
		{"Value.Variant", func() error { _, err := value.Variant(); return err }},
		{"Value.AsChild", func() error { _, _, err := value.AsChild(); return err }},
		{"ValueRef.Tag", func() error { _, err := ref.Tag(); return err }},
		{"ValueRef.Variant", func() error { _, err := ref.Variant(); return err }},
		{"ValueRef.AsChild", func() error { _, _, err := ref.AsChild(); return err }},
		{"Signal.Snapshot", func() error { _, err := signal.Snapshot(); return err }},
		{"Signal.Variant", func() error { _, err := signal.Variant(); return err }},
	}

	var wait sync.WaitGroup
	start := make(chan struct{})
	for _, reader := range readers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			<-start
			for range 200 {
				requireOpenOrClosed(t, reader.name, reader.read())
			}
		}()
	}
	for _, closer := range []func() error{value.Close, signal.Close} {
		wait.Add(1)
		go func() {
			defer wait.Done()
			<-start
			runtime.Gosched()
			closer()
		}()
	}
	close(start)
	wait.Wait()

	// The ref outlives its parent. Every projection through it must report the
	// closed parent rather than follow the pointer it captured while open.
	if _, err := ref.Tag(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("ValueRef.Tag after parent Close = %v, want ErrInvalidHandle", err)
	}
	if _, err := ref.Variant(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("ValueRef.Variant after parent Close = %v, want ErrInvalidHandle", err)
	}
	if _, _, err := ref.AsChild(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("ValueRef.AsChild after parent Close = %v, want ErrInvalidHandle", err)
	}
	if _, err := value.Variant(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Value.Variant after Close = %v, want ErrInvalidHandle", err)
	}
	if _, err := signal.Snapshot(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Signal.Snapshot after Close = %v, want ErrInvalidHandle", err)
	}
}

// Close is idempotent through the write lock and the nil-pointer check alone,
// with no sync.Once in front of it: the losing goroutines block on the lock
// and then find the pointer already cleared. Run this with -race, where a
// double release would show up as a native double free.
func TestConcurrentDoubleClose(t *testing.T) {
	child, err := NewChild(11)
	if err != nil {
		t.Fatal(err)
	}

	const closers = 16
	var wait sync.WaitGroup
	start := make(chan struct{})
	for range closers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			<-start
			for range 4 {
				if err := child.Close(); err != nil {
					t.Errorf("Close() = %v, want nil", err)
				}
			}
		}()
	}
	close(start)
	wait.Wait()

	if err := child.Close(); err != nil {
		t.Fatalf("Close after concurrent Close = %v, want nil", err)
	}
	if _, err := child.Get(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Get after Close = %v, want ErrInvalidHandle", err)
	}

	var closed *Child
	if err := closed.Close(); err != nil {
		t.Fatalf("Close on a nil handle = %v, want nil", err)
	}
}
