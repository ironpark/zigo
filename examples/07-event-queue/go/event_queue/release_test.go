package event_queue

import (
	"errors"
	"testing"
)

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

// ExtractSamplesChecked combines `.returns = .caller` with a fallible return.
// The release call belongs on the success path only: a failure allocated
// nothing, so calling the release symbol would free a buffer that never existed.
func TestFallibleCallerOwnedSliceReleasesOnlyOnSuccess(t *testing.T) {
	queue, err := NewEventQueue("release-checked", 4, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()

	before := LiveSamples()
	if _, err := queue.ExtractSamplesChecked(); !errors.Is(err, ErrEmpty) {
		t.Fatalf("ExtractSamplesChecked() on an empty queue err = %v, want ErrEmpty", err)
	}
	if got := LiveSamples(); got != before {
		t.Fatalf("LiveSamples() = %d after a failed call, want %d", got, before)
	}

	if err := queue.Enqueue(1, 7); err != nil {
		t.Fatal(err)
	}
	first := must(queue.ExtractSamplesChecked())
	if len(first) != 2 || first[0] != 1 || first[1] != 7 {
		t.Fatalf("ExtractSamplesChecked() = %v, want [1 7]", first)
	}
	if got := LiveSamples(); got != 0 {
		t.Fatalf("LiveSamples() = %d after one successful call, want 0", got)
	}

	first[0] = 99
	second := must(queue.ExtractSamplesChecked())
	if second[0] != 1 {
		t.Fatalf("ExtractSamplesChecked() aliased released memory: second[0] = %v", second[0])
	}
	if first[0] != 99 || first[1] != 7 {
		t.Fatalf("first slice was invalidated by the second call: %v", first)
	}
	if got := LiveSamples(); got != 0 {
		t.Fatalf("LiveSamples() = %d after two successful calls, want 0", got)
	}
}
