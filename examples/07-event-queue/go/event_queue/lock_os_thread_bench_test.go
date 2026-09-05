package event_queue

import (
	"runtime"
	"testing"

	raw "example.com/zigo/event-queue/bridge/cgo"
)

// enqueueUnlocked is Enqueue with the runtime.LockOSThread pair taken out and
// nothing else changed: the same handle check, the same native call, the same
// callback-panic sweep. Benchmarking the two against each other prices the
// thread pinning that errorForCode needs to read the panic message.
func (e *EventQueue) enqueueUnlocked(id uint64, value int32) error {
	ptr, err := zigoCheckedPointer("EventQueue.Enqueue receiver", e)
	if err != nil {
		return err
	}
	defer e.zigoRelease()
	code := raw.EventQueueEnqueue(ptr, id, value)
	if zigoCallbackPanicPending() {
		for _, handle := range e.callbackHandles {
			zigoRethrowCallbackPanic("EventQueue.Enqueue", handle)
		}
	}
	if code != 0 {
		return zigoPoisonAfterPanic(errorForCode("EventQueue.Enqueue", code), e)
	}
	return nil
}

func benchQueue(b *testing.B) *EventQueue {
	b.Helper()
	queue, err := NewEventQueue("bench", 4, PolicyDropOldest, func(uint64, int32) int32 { return 0 })
	if err != nil {
		b.Fatalf("NewEventQueue: %v", err)
	}
	b.Cleanup(func() { queue.Close() })
	return queue
}

func BenchmarkEnqueue(b *testing.B) {
	queue := benchQueue(b)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if err := queue.Enqueue(uint64(i), int32(i)); err != nil {
			b.Fatalf("Enqueue: %v", err)
		}
	}
}

func BenchmarkEnqueueUnlocked(b *testing.B) {
	queue := benchQueue(b)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if err := queue.enqueueUnlocked(uint64(i), int32(i)); err != nil {
			b.Fatalf("enqueueUnlocked: %v", err)
		}
	}
}

// The pair on its own, with no call in between, is the floor of what the
// generated wrapper pays for pinning.
func BenchmarkLockOSThreadPair(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		runtime.LockOSThread()
		runtime.UnlockOSThread()
	}
}
