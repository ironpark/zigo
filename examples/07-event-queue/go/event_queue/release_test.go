package event_queue

import "testing"

// ExtractSamples returns a library-allocated buffer. The generated binding must
// copy it and then call the declared release function, so the returned slice
// stays valid while the native leak counter returns to zero.
func TestCallerOwnedSliceReturnIsCopiedAndReleased(t *testing.T) {
	queue, err := NewEventQueue("release", 4, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()
	if err := queue.Enqueue(1, 7); err != nil {
		t.Fatal(err)
	}

	first := must(queue.ExtractSamples())
	if len(first) != 2 || first[0] != 1 || first[1] != 7 {
		t.Fatalf("ExtractSamples() = %v, want [1 7]", first)
	}
	if got := LiveSamples(); got != 0 {
		t.Fatalf("LiveSamples() = %d after one call, want 0", got)
	}

	first[0] = 99
	second := must(queue.ExtractSamples())
	if second[0] != 1 {
		t.Fatalf("ExtractSamples() aliased released memory: second[0] = %v", second[0])
	}
	if first[0] != 99 || first[1] != 7 {
		t.Fatalf("first slice was invalidated by the second call: %v", first)
	}
	if got := LiveSamples(); got != 0 {
		t.Fatalf("LiveSamples() = %d after two calls, want 0", got)
	}
}
