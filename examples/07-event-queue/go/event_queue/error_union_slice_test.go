package event_queue

import (
	"errors"
	"testing"
)

// SampleValuesChecked returns `![]const f32`. The error travels in the code and
// the payload in the same `out_result_ptr` / `out_result_len` pair a plain slice
// return uses, so a failure must surface as a nil slice with the mapped error
// and a success must still be copied out of native memory.
func TestFallibleSliceReturnCarriesBothOutcomes(t *testing.T) {
	queue, err := NewEventQueue("checked", 2, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer queue.Close()

	// The shim never writes the out parameters on the error path.
	empty, err := queue.SampleValuesChecked()
	if !errors.Is(err, ErrEmpty) {
		t.Fatalf("SampleValuesChecked() on an empty queue err = %v, want ErrEmpty", err)
	}
	if empty != nil {
		t.Fatalf("SampleValuesChecked() on an empty queue = %v, want nil", empty)
	}

	if err := queue.Enqueue(1, 7); err != nil {
		t.Fatal(err)
	}
	first := must(queue.SampleValuesChecked())
	if len(first) != 3 || first[0] != 0.25 || first[2] != 3.75 {
		t.Fatalf("SampleValuesChecked() = %v, want [0.25 1.5 3.75]", first)
	}

	first[0] = 99
	second := must(queue.SampleValuesChecked())
	if second[0] != 0.25 {
		t.Fatalf("SampleValuesChecked() aliased native memory: second[0] = %v", second[0])
	}
}
