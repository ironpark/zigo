package event_queue

import (
	"errors"
	"fmt"
	"io"
	"runtime"
	"sync"
	"testing"
	"time"
)

var _ EventQueueCreateObserver = func(uint64, int32) int32 { return 0 }
var _ EventQueueCloneObserver = func(uint64, int32) int32 { return 0 }

// A generated handle closes like any other Go resource.
var _ io.Closer = (*EventQueue)(nil)

// must unwraps a generated call whose only failure mode here would be a nil or
// closed handle.
func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

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

	if got := must(queue.Name()); got != "중요 이벤트" {
		t.Fatalf("Name() = %q", got)
	}
	if got := must(queue.Capacity()); got != 2 {
		t.Fatalf("Capacity() = %d, want 2", got)
	}
	if got := must(queue.Policy()); got != PolicyReject {
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
	if got := must(queue.Processed()); got != 2 {
		t.Fatalf("Processed() = %d, want 2", got)
	}
	want := []observedEvent{{id: 10, value: 100}, {id: 11, value: 200}}
	if fmt.Sprint(observed) != fmt.Sprint(want) {
		t.Fatalf("observed = %v, want %v", observed, want)
	}
}

func TestNumericSliceReturnIsCopied(t *testing.T) {
	queue, err := NewEventQueue("samples", 2, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()

	first := must(queue.SampleValues())
	first[0] = 99
	second := must(queue.SampleValues())
	if second[0] != 0.25 {
		t.Fatalf("SampleValues() aliased native memory: second[0] = %v", second[0])
	}
}

// Clone is not named like a constructor; only its `.returns = .caller`
// metadata makes it hand over an owned handle.
func TestCloneReturnsAnIndependentOwnedHandle(t *testing.T) {
	queue, err := NewEventQueue("source", 2, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()
	if err := queue.Enqueue(1, 10); err != nil {
		t.Fatal(err)
	}

	var cloned []observedEvent
	copied, err := queue.Clone(func(id uint64, value int32) int32 {
		cloned = append(cloned, observedEvent{id: id, value: value})
		return 0
	})
	if err != nil {
		t.Fatal(err)
	}
	defer copied.Close()

	if got := must(copied.Name()); got != "source" {
		t.Fatalf("clone Name() = %q, want \"source\"", got)
	}
	if got := LiveQueues(); got != 2 {
		t.Fatalf("LiveQueues() = %d, want 2", got)
	}
	// The clone drains through its own observer, and the original keeps its
	// own events, which is what an owned handle rather than an alias means.
	if got, err := copied.Process(1); err != nil || got != 1 {
		t.Fatalf("clone Process(1) = (%d, %v), want (1, nil)", got, err)
	}
	if fmt.Sprint(cloned) != fmt.Sprint([]observedEvent{{id: 1, value: 10}}) {
		t.Fatalf("clone observed = %v", cloned)
	}
	if got := must(queue.Len()); got != 1 {
		t.Fatalf("original Len() = %d, want 1", got)
	}

	if err := copied.Close(); err != nil {
		t.Fatal(err)
	}
	if got := LiveQueues(); got != 1 {
		t.Fatalf("LiveQueues() after clone Close = %d, want 1", got)
	}
	if _, err := copied.Clone(func(uint64, int32) int32 { return 0 }); err == nil {
		t.Fatal("Clone on a closed handle returned no error")
	}
}

// The Zig parameter is `?*const EventQueue`, so a nil handle is a value the
// API accepts rather than a *HandleError.
func TestMergeFromAcceptsANilOptionalHandle(t *testing.T) {
	observer := func(uint64, int32) int32 { return 0 }
	target, err := NewEventQueue("target", 4, PolicyReject, observer)
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	source, err := NewEventQueue("source", 4, PolicyReject, observer)
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	if err := source.Enqueue(1, 10); err != nil {
		t.Fatal(err)
	}
	if err := source.Enqueue(2, 20); err != nil {
		t.Fatal(err)
	}

	if got, err := target.MergeFrom(nil); err != nil || got != 0 {
		t.Fatalf("MergeFrom(nil) = (%d, %v), want (0, nil)", got, err)
	}
	if got := must(target.Len()); got != 0 {
		t.Fatalf("Len() after nil merge = %d, want 0", got)
	}
	if got, err := target.MergeFrom(source); err != nil || got != 2 {
		t.Fatalf("MergeFrom(source) = (%d, %v), want (2, nil)", got, err)
	}
	if got := must(target.Len()); got != 2 {
		t.Fatalf("Len() after merge = %d, want 2", got)
	}

	// Optional only means the argument may be absent; a handle that is present
	// but already closed is still a caller error.
	source.Close()
	if _, err := target.MergeFrom(source); err == nil {
		t.Fatal("MergeFrom with a closed source returned no error")
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
	if got := must(queue.Dropped()); got != 1 {
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
	if got := must(queue.Clear()); got != 2 {
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

func TestObserverPanicIsRethrown(t *testing.T) {
	queue, err := NewEventQueue("panic", 1, PolicyReject, func(uint64, int32) int32 {
		panic("deliberate observer panic")
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue(1, 10); err != nil {
		t.Fatal(err)
	}
	// The Zig side answers -3 with ObserverPanicked and leaves the event in
	// place; the Go caller sees the panic itself, then a consistent queue.
	expectCallbackPanic(t, "EventQueue.Process", "deliberate observer panic", func() { _, _ = queue.Process(1) })
	if got := must(queue.Len()); got != 1 {
		t.Fatalf("Len() after observer panic = %d, want 1", got)
	}
	queue.Close()
	queue.Close()
	assertNoLiveQueueResources(t)
}

func TestRetainedMethodCallbackHandlesAreReplacedAndClosed(t *testing.T) {
	before := activeCallbackHandleCount()
	queue, err := NewEventQueue("replace observer", 1, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	if err := queue.SetObserver(func(uint64, int32) int32 { return 1 }); err != nil {
		t.Fatal(err)
	}
	if err := queue.SetObserver(func(uint64, int32) int32 { return 2 }); err != nil {
		t.Fatal(err)
	}
	if got := activeCallbackHandleCount(); got != before+2 {
		t.Fatalf("active callback handles after replacement = %d, want %d", got, before+2)
	}
	if err := queue.Close(); err != nil {
		t.Fatal(err)
	}
	if got := activeCallbackHandleCount(); got != before {
		t.Fatalf("active callback handles after Close = %d, want %d", got, before)
	}
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

// expectCallbackPanic runs call and requires it to panic with the
// *CallbackPanicError the binding rethrows for a Go callback panic. It
// returns the error for further inspection.
func expectCallbackPanic(t *testing.T, operation string, value any, call func()) *CallbackPanicError {
	t.Helper()
	var recovered any
	func() {
		defer func() { recovered = recover() }()
		call()
	}()
	err, ok := recovered.(error)
	if !ok {
		t.Fatalf("recovered %v (%T), want *CallbackPanicError", recovered, recovered)
	}
	var panicErr *CallbackPanicError
	if !errors.As(err, &panicErr) {
		t.Fatalf("recovered %v, want *CallbackPanicError", err)
	}
	if !errors.Is(err, ErrCallbackPanic) {
		t.Fatalf("errors.Is(%v, ErrCallbackPanic) = false", err)
	}
	if panicErr.Operation != operation {
		t.Fatalf("Operation = %q, want %q", panicErr.Operation, operation)
	}
	if panicErr.Value != value {
		t.Fatalf("Value = %v, want %v", panicErr.Value, value)
	}
	if len(panicErr.Stack) == 0 {
		t.Fatal("Stack is empty")
	}
	return panicErr
}
