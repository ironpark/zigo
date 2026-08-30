package event_queue

import (
	"errors"
	"fmt"
	"runtime"
	"sync"
	"testing"
	"time"
)

var _ EventQueueObserver = func(uint64, int32) int32 { return 0 }

type observedEvent struct {
	id    uint64
	value int32
}

func TestRejectQueueEndToEnd(t *testing.T) {
	var observed []observedEvent
	queue, err := NewEventQueue("중요 이벤트", 2, PolicyReject, func(id uint64, value int32) int32 {
		observed = append(observed, observedEvent{id: id, value: value})
		return 0
	})
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()

	if got := queue.Name(); got != "중요 이벤트" {
		t.Fatalf("Name() = %q", got)
	}
	if got := queue.Capacity(); got != 2 {
		t.Fatalf("Capacity() = %d, want 2", got)
	}
	if got := queue.Policy(); got != PolicyReject {
		t.Fatalf("Policy() = %v, want %v", got, PolicyReject)
	}
	if err := queue.Enqueue(10, 100); err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue(11, 200); err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue(12, 300); !errors.Is(err, ErrFull) {
		t.Fatalf("third Enqueue() error = %v, want %v", err, ErrFull)
	}
	if got, err := queue.Process(1); err != nil || got != 1 {
		t.Fatalf("Process(1) = (%d, %v), want (1, nil)", got, err)
	}
	if got, err := queue.Process(10); err != nil || got != 1 {
		t.Fatalf("Process(10) = (%d, %v), want (1, nil)", got, err)
	}
	if _, err := queue.Process(1); !errors.Is(err, ErrEmpty) {
		t.Fatalf("empty Process() error = %v, want %v", err, ErrEmpty)
	}
	if _, err := queue.Process(0); !errors.Is(err, ErrInvalidLimit) {
		t.Fatalf("Process(0) error = %v, want %v", err, ErrInvalidLimit)
	}
	if got := queue.Processed(); got != 2 {
		t.Fatalf("Processed() = %d, want 2", got)
	}
	want := []observedEvent{{id: 10, value: 100}, {id: 11, value: 200}}
	if fmt.Sprint(observed) != fmt.Sprint(want) {
		t.Fatalf("observed = %v, want %v", observed, want)
	}
}

func TestDropOldestPolicy(t *testing.T) {
	var observed []uint64
	queue, err := NewEventQueue("lossy", 2, PolicyDropOldest, func(id uint64, _ int32) int32 {
		observed = append(observed, id)
		return 0
	})
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()

	for id := uint64(1); id <= 3; id++ {
		if err := queue.Enqueue(id, int32(id*10)); err != nil {
			t.Fatal(err)
		}
	}
	if got := queue.Dropped(); got != 1 {
		t.Fatalf("Dropped() = %d, want 1", got)
	}
	if got, err := queue.Process(2); err != nil || got != 2 {
		t.Fatalf("Process(2) = (%d, %v), want (2, nil)", got, err)
	}
	if fmt.Sprint(observed) != "[2 3]" {
		t.Fatalf("observed IDs = %v, want [2 3]", observed)
	}
	if err := queue.Enqueue(4, 40); err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue(5, 50); err != nil {
		t.Fatal(err)
	}
	if got := queue.Clear(); got != 2 {
		t.Fatalf("Clear() = %d, want 2", got)
	}
}

func TestConstructorFailuresReleaseObserver(t *testing.T) {
	observer := func(uint64, int32) int32 { return 0 }
	if _, err := NewEventQueue("", 1, PolicyReject, observer); !errors.Is(err, ErrInvalidName) {
		t.Fatalf("empty-name constructor error = %v, want %v", err, ErrInvalidName)
	}
	if _, err := NewEventQueue("queue", 0, PolicyReject, observer); !errors.Is(err, ErrInvalidCapacity) {
		t.Fatalf("zero-capacity constructor error = %v, want %v", err, ErrInvalidCapacity)
	}
	assertNoLiveQueueResources(t)
}

func TestObserverPanicBecomesTypedError(t *testing.T) {
	queue, err := NewEventQueue("panic", 1, PolicyReject, func(uint64, int32) int32 {
		panic("deliberate observer panic")
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue(1, 10); err != nil {
		t.Fatal(err)
	}
	if _, err := queue.Process(1); !errors.Is(err, ErrObserverPanicked) {
		t.Fatalf("Process() error = %v, want %v", err, ErrObserverPanicked)
	}
	if got := queue.Len(); got != 1 {
		t.Fatalf("Len() after observer panic = %d, want 1", got)
	}
	queue.Close()
	queue.Close()
	assertNoLiveQueueResources(t)
}

func TestConcurrentIndependentQueueLifecycles(t *testing.T) {
	const workers = 8
	const iterations = 30
	var wait sync.WaitGroup
	errs := make(chan error, workers)

	for worker := range workers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			for iteration := range iterations {
				observed := 0
				queue, err := NewEventQueue(fmt.Sprintf("worker-%d-%d", worker, iteration), 4, PolicyReject, func(uint64, int32) int32 {
					observed++
					return 0
				})
				if err != nil {
					errs <- err
					return
				}
				for id := uint64(0); id < 4; id++ {
					if err := queue.Enqueue(id, int32(id)); err != nil {
						queue.Close()
						errs <- err
						return
					}
				}
				count, err := queue.Process(4)
				queue.Close()
				queue.Close()
				if err != nil || count != 4 || observed != 4 {
					errs <- fmt.Errorf("worker %d iteration %d: count=%d observed=%d err=%v", worker, iteration, count, observed, err)
					return
				}
			}
		}()
	}
	wait.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	assertNoLiveQueueResources(t)
}

func TestRuntimeCleanupFallbackReleasesQueueAndObserver(t *testing.T) {
	assertNoLiveQueueResources(t)
	func() {
		queue, err := NewEventQueue("cleanup fallback", 2, PolicyReject, func(uint64, int32) int32 { return 0 })
		if err != nil {
			t.Fatal(err)
		}
		if err := queue.Enqueue(1, 10); err != nil {
			t.Fatal(err)
		}
		if got := LiveQueues(); got != 1 {
			t.Fatalf("LiveQueues() before fallback = %d, want 1", got)
		}
		if got := activeCallbackHandleCount(); got != 1 {
			t.Fatalf("active callback handles before fallback = %d, want 1", got)
		}
		runtime.KeepAlive(queue)
	}()
	waitForRuntimeCleanup(t)
}

func TestExplicitCloseStopsRuntimeCleanup(t *testing.T) {
	assertNoLiveQueueResources(t)
	func() {
		queue, err := NewEventQueue("explicit close", 1, PolicyReject, func(uint64, int32) int32 { return 0 })
		if err != nil {
			t.Fatal(err)
		}
		queue.Close()
		queue.Close()
	}()
	for range 3 {
		runtime.GC()
		runtime.Gosched()
	}
	assertNoLiveQueueResources(t)
}

func waitForRuntimeCleanup(t *testing.T) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		runtime.GC()
		runtime.Gosched()
		if activeCallbackHandleCount() == 0 && LiveQueues() == 0 {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("runtime cleanup timed out: callback handles=%d live queues=%d", activeCallbackHandleCount(), LiveQueues())
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func assertNoLiveQueueResources(t *testing.T) {
	t.Helper()
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("active callback handles = %d, want 0", got)
	}
	if got := LiveQueues(); got != 0 {
		t.Fatalf("LiveQueues() = %d, want 0", got)
	}
}
