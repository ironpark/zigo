package raw

import (
	"sync"
	"sync/atomic"
	"testing"
)

// The registry lookup is lock-free, so delete-vs-invoke correctness rests on
// the per-entry closing flag alone: an acquire either registers itself before
// the flag is set, and DeleteCallbackHandle waits for it, or it observes the
// flag and reports the token as gone. Nothing may run a callback after Delete
// has returned, and every token must drain.
func TestCallbackRegistryChurnUnderConcurrentInvocations(t *testing.T) {
	baseline := ActiveCallbackHandleCount()

	const tokens = 16
	const invokers = 4
	var wait sync.WaitGroup
	for range tokens {
		wait.Add(1)
		go func() {
			defer wait.Done()
			var deleted atomic.Bool
			token := NewCallbackHandle(func() {})
			var inner sync.WaitGroup
			for range invokers {
				inner.Add(1)
				go func() {
					defer inner.Done()
					for range 500 {
						entry, value, ok := acquireCallback(token)
						if !ok {
							continue
						}
						if deleted.Load() {
							t.Error("acquired a token after DeleteCallbackHandle returned")
						}
						if value == nil {
							t.Error("acquired entry carried no callback value")
						}
						releaseCallback(entry)
					}
				}()
			}
			DeleteCallbackHandle(token)
			deleted.Store(true)
			inner.Wait()

			if _, _, ok := acquireCallback(token); ok {
				t.Error("deleted token is still acquirable")
			}
			DeleteCallbackHandle(token)
		}()
	}
	wait.Wait()

	if got := ActiveCallbackHandleCount(); got != baseline {
		t.Fatalf("active callback handles = %d, want %d", got, baseline)
	}
	DeleteCallbackHandle(0)
	DeleteCallbackHandle(^uintptr(0))
	if got := ActiveCallbackHandleCount(); got != baseline {
		t.Fatalf("active callback handles after no-op deletes = %d, want %d", got, baseline)
	}
}

// Tokens must stay unique and non-zero even when handles are created
// concurrently, since a native side stores one as its userdata word.
func TestCallbackHandleTokensAreUniqueAndNonZero(t *testing.T) {
	const goroutines = 8
	const perGoroutine = 64
	tokens := make(chan uintptr, goroutines*perGoroutine)
	var wait sync.WaitGroup
	for range goroutines {
		wait.Add(1)
		go func() {
			defer wait.Done()
			for range perGoroutine {
				tokens <- NewCallbackHandle(struct{}{})
			}
		}()
	}
	wait.Wait()
	close(tokens)

	seen := make(map[uintptr]struct{}, goroutines*perGoroutine)
	for token := range tokens {
		if token == 0 {
			t.Fatal("NewCallbackHandle returned the reserved zero token")
		}
		if _, duplicate := seen[token]; duplicate {
			t.Fatalf("NewCallbackHandle returned duplicate token %d", token)
		}
		seen[token] = struct{}{}
		DeleteCallbackHandle(token)
	}
}
