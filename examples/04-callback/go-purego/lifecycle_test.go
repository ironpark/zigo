package callback

import (
	"errors"
	"runtime"
	"sync"
	"testing"
	"time"
)

// Close serializes against calls that are already inside the native boundary,
// so a racing caller either completes or is told the handle is closed. Run
// this with -race: an unserialized Close would be a use-after-free.
func TestConcurrentCallsRacingClose(t *testing.T) {
	context, err := NewCallbackContext(func(value int32) (int32, error) { return value + 1, nil })
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
				got, err := context.Run(7)
				if err == nil {
					if got != 8 {
						t.Errorf("Run(7) = %d, want 8", got)
					}
					continue
				}
				var handleErr *HandleError
				if !errors.As(err, &handleErr) {
					t.Errorf("Run(7) after Close = %#v, want *HandleError", err)
				}
			}
		}()
	}
	wait.Add(1)
	go func() {
		defer wait.Done()
		<-start
		runtime.Gosched()
		context.Close()
	}()
	close(start)
	wait.Wait()

	if _, err := context.Run(7); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Run after Close = %v, want ErrInvalidHandle", err)
	}
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("active callback handles = %d, want 0", got)
	}
}

// A handle the caller drops without closing is still released: the cleanup
// registered at construction frees the native context and its retained
// callback once the handle becomes unreachable.
func TestAbandonedHandleIsReclaimed(t *testing.T) {
	baseline := activeCallbackHandleCount()

	func() {
		context, err := NewCallbackContext(func(value int32) (int32, error) { return value + 1, nil })
		if err != nil {
			t.Fatal(err)
		}
		got, err := context.Run(7)
		if err != nil {
			t.Fatal(err)
		}
		if got != 8 {
			t.Fatalf("Run(7) = %d, want 8", got)
		}
		// No Close and no KeepAlive: the handle goes out of scope owning a
		// live callback registration.
	}()

	deadline := time.Now().Add(5 * time.Second)
	for activeCallbackHandleCount() != baseline {
		if time.Now().After(deadline) {
			t.Fatalf("abandoned handle was not reclaimed: active callback handles = %d, want %d",
				activeCallbackHandleCount(), baseline)
		}
		runtime.GC()
		runtime.Gosched()
		time.Sleep(10 * time.Millisecond)
	}
}
