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

func TestValueStructSlices(t *testing.T) {
	queue, err := NewEventQueue("estimate", 4, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()
	if err := queue.Enqueue(1, 10); err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue(2, 20); err != nil {
		t.Fatal(err)
	}

	output := make([]Stats, 2)
	if written, err := queue.Estimate(output); err != nil || written != 2 {
		t.Fatalf("Estimate() = (%d, %v), want (2, nil)", written, err)
	}
	for index, value := range output {
		if value.Len != 2 || value.Capacity != 4 || value.Policy != PolicyReject || value.Saturated {
			t.Fatalf("Estimate()[%d] = %+v, want queue summary", index, value)
		}
	}
}

func TestValueStructSliceInputAndReturn(t *testing.T) {
	queue, err := NewEventQueue("slice-values", 4, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()

	input := []Stats{{Len: 1, Capacity: 4, Policy: PolicyReject}, {Len: 2, Capacity: 4, Policy: PolicyDropOldest}}
	if got := must(queue.AcceptStats(input)); got != 2 {
		t.Fatalf("AcceptStats() = %d, want 2", got)
	}
	first := must(queue.SampleStats())
	if len(first) != 2 || first[0].Capacity != 4 {
		t.Fatalf("SampleStats() = %+v, want two snapshots", first)
	}
	first[0].Capacity = 99
	second := must(queue.SampleStats())
	if second[0].Capacity != 4 {
		t.Fatalf("SampleStats() aliased native memory: second[0] = %+v", second[0])
	}
}

// The `...Into(dst)` contract: the call fills exactly as many entries as it
// reports written, and leaves everything past that alone. Nothing is allocated
// on either side, and `Limits` has no bool field, so the buffer itself is what
// the native call writes into.
func TestValueStructOutSliceStopsAtWritten(t *testing.T) {
	queue, err := NewEventQueue("written", 8, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()
	if err := queue.Enqueue(1, 10); err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue(2, 20); err != nil {
		t.Fatal(err)
	}

	sentinel := Limits{Capacity: 4242, Policy: PolicyDropOldest}
	dst := []Limits{sentinel, sentinel, sentinel, sentinel}
	written := must(queue.LimitsInto(dst))
	if written != 2 {
		t.Fatalf("LimitsInto() = %d, want 2", written)
	}
	for index, value := range dst[:written] {
		if value.Capacity != 8 || value.Policy != PolicyReject {
			t.Fatalf("LimitsInto()[%d] = %+v, want the queue limits", index, value)
		}
	}
	for index, value := range dst[written:] {
		if value != sentinel {
			t.Fatalf("LimitsInto() overwrote element %d past written: %+v", int(written)+index, value)
		}
	}

	// A scalar buffer follows the same rule, and a buffer too small to hold
	// the result reports nothing written rather than a partial answer.
	samples := []float32{-1, -1, -1, -1, -1}
	filled := must(queue.ExtractSamplesInto(samples))
	if filled != 3 {
		t.Fatalf("ExtractSamplesInto() = %d, want 3", filled)
	}
	if samples[0] != 2 || samples[1] != 10 || samples[2] != 20 {
		t.Fatalf("ExtractSamplesInto() filled %v, want the count followed by the values", samples[:filled])
	}
	for index, value := range samples[filled:] {
		if value != -1 {
			t.Fatalf("ExtractSamplesInto() overwrote element %d past written: %v", int(filled)+index, value)
		}
	}
	if short := must(queue.ExtractSamplesInto(make([]float32, 1))); short != 0 {
		t.Fatalf("ExtractSamplesInto(short) = %d, want 0", short)
	}
}

// A castable element (no bool field) is handed back by reinterpreting the copy
// the raw layer already made, so the values must still match and the slice must
// still be independent of both the handle and the native buffer.
func TestCastableStructSliceReturnKeepsItsValues(t *testing.T) {
	queue, err := NewEventQueue("limits-view", 4, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()

	borrowed := must(queue.SampleLimits())
	if len(borrowed) != 2 {
		t.Fatalf("SampleLimits() = %+v, want two rows", borrowed)
	}
	if borrowed[0] != (Limits{Capacity: 4, Policy: PolicyReject}) {
		t.Fatalf("SampleLimits()[0] = %+v, want the queue limits", borrowed[0])
	}
	if borrowed[1] != (Limits{Capacity: 5, Policy: PolicyReject}) {
		t.Fatalf("SampleLimits()[1] = %+v, want the queue limits plus one", borrowed[1])
	}
	borrowed[0].Capacity = 99
	if again := must(queue.SampleLimits()); again[0].Capacity != 4 {
		t.Fatalf("SampleLimits() aliased native memory: again[0] = %+v", again[0])
	}

	// `.returns = .caller` copies the native buffer, releases it, and only then
	// reinterprets the copy, so the values outlive the release.
	if err := queue.Enqueue(1, 10); err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue(2, 20); err != nil {
		t.Fatal(err)
	}
	owned := must(queue.ExtractLimits())
	if len(owned) != 2 {
		t.Fatalf("ExtractLimits() = %+v, want two rows", owned)
	}
	for index, row := range owned {
		want := Limits{Capacity: 4 + uint32(index), Policy: PolicyReject}
		if row != want {
			t.Fatalf("ExtractLimits()[%d] = %+v, want %+v", index, row, want)
		}
	}
	if got := LiveLimits(); got != 0 {
		t.Fatalf("LiveLimits() = %d after the call, want 0", got)
	}
	owned[0].Capacity = 99
	if second := must(queue.ExtractLimits()); second[0].Capacity != 4 {
		t.Fatalf("ExtractLimits() aliased released memory: second[0] = %+v", second[0])
	}
}
