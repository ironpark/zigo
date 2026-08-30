package native

import (
	"sync"
	"testing"
)

func TestDeleteWaitsForInflightAndDeletedTokenCannotAcquire(t *testing.T) {
	token := NewCallbackHandle(func(uint64, int32) int32 { return 0 })
	entry, _, ok := acquireCallback(token)
	if !ok {
		t.Fatal("new token was not acquirable")
	}
	var wait sync.WaitGroup
	wait.Add(1)
	done := make(chan struct{})
	go func() {
		defer wait.Done()
		DeleteCallbackHandle(token)
		close(done)
	}()
	select {
	case <-done:
		t.Fatal("delete returned while callback was in flight")
	default:
	}
	releaseCallback(entry)
	wait.Wait()
	if _, _, ok := acquireCallback(token); ok {
		t.Fatal("deleted token remained acquirable")
	}
	if got := ActiveCallbackHandleCount(); got != 0 {
		t.Fatalf("active handles = %d", got)
	}
}
