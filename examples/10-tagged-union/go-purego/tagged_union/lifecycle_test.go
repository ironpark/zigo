package tagged_union

import (
	"errors"
	"runtime"
	"sync"
	"testing"
)

// A binding without callbacks gets the same Close serialization as one with
// them. Run this with -race: before every handle carried a mutex, a Close
// racing an in-flight call was a use-after-free. Like the rest of this tree it
// runs from TestPuregoTaggedUnion, once the library is loaded.
func assertConcurrentCallsRacingClose(t *testing.T) {
	t.Helper()

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
