package contracts

import (
	"errors"
	"runtime"
	"sync"
	"testing"
)

// CallsRacingClose checks that racing calls either succeed or return a typed
// handle error, and calls after Close report the invalid-handle sentinel.
// Run cgo adapters with -race to also check Go-side synchronization.
func CallsRacingClose[T comparable](t *testing.T, call func() (T, error), closeHandle func() error, want T, invalid error, isHandleError func(error) bool) {
	t.Helper()
	const callers = 8
	var wait sync.WaitGroup
	start := make(chan struct{})
	for range callers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			<-start
			for range 200 {
				got, err := call()
				if err == nil {
					if got != want {
						t.Errorf("call = %v, want %v", got, want)
					}
					continue
				}
				if !isHandleError(err) {
					t.Errorf("call racing Close = %#v, want typed handle error", err)
				}
			}
		}()
	}
	wait.Add(1)
	go func() {
		defer wait.Done()
		<-start
		runtime.Gosched()
		if err := closeHandle(); err != nil {
			t.Errorf("Close = %v, want nil", err)
		}
	}()
	close(start)
	wait.Wait()

	if _, err := call(); !errors.Is(err, invalid) {
		t.Fatalf("call after Close = %v, want %v", err, invalid)
	}
}
