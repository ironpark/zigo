package event_queue

import "testing"

// assertValueStructRoundTrip exercises the `extern struct` path. Go sees plain
// values; the pointer the C ABI wants is taken inside the generated code.
func assertValueStructRoundTrip(t *testing.T, queue *EventQueue) {
	t.Helper()

	// A struct return arrives filled through an out parameter and comes back
	// as a value.
	before := must(queue.Stats())
	if before.Capacity == 0 {
		t.Fatalf("Stats() = %+v, want a non-zero capacity", before)
	}
	if before.Policy != must(queue.Policy()) {
		t.Fatalf("Stats().Policy = %v, want %v", before.Policy, must(queue.Policy()))
	}
	if before.Len != uint32(must(queue.Len())) {
		t.Fatalf("Stats().Len = %d, want %d", before.Len, must(queue.Len()))
	}

	// A struct parameter travels the other way and survives the round trip.
	updated := Limits{Capacity: before.Capacity + 3, Policy: PolicyDropOldest}
	if err := queue.ApplyLimits(updated); err != nil {
		t.Fatal(err)
	}
	if got := must(queue.Limits()); got != updated {
		t.Fatalf("Limits() = %+v, want %+v", got, updated)
	}
	if got := must(queue.Stats()); got.Capacity != updated.Capacity || got.Policy != updated.Policy {
		t.Fatalf("Stats() = %+v, want capacity %d policy %v", got, updated.Capacity, updated.Policy)
	}

	// The bool field crosses as uint8 and is restored on the Go side.
	if got := must(queue.Stats()).Saturated; got != (must(queue.Len()) >= must(queue.Capacity())) {
		t.Fatalf("Stats().Saturated = %v, want %v", got, must(queue.Len()) >= must(queue.Capacity()))
	}

	// Errors still travel as codes; the struct payload is untouched.
	if err := queue.ApplyLimits(Limits{Capacity: 0, Policy: PolicyReject}); err == nil {
		t.Fatal("ApplyLimits with a zero capacity unexpectedly succeeded")
	}
}

func TestValueStructParametersAndReturns(t *testing.T) {
	queue, err := NewEventQueue("stats", 4, PolicyReject, func(id uint64, value int32) int32 { return value })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()
	assertValueStructRoundTrip(t, queue)
}
