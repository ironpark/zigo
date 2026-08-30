package type_relations

import "testing"

func TestAccumulatorAcceptsCounter(t *testing.T) {
	counter, err := NewCounter(40)
	if err != nil {
		t.Fatal(err)
	}
	defer counter.Close()

	accumulator, err := NewAccumulator()
	if err != nil {
		t.Fatal(err)
	}
	defer accumulator.Close()

	if got := accumulator.Absorb(counter); got != 40 {
		t.Fatalf("Absorb(counter) = %d, want 40", got)
	}
	if got := counter.Add(2); got != 42 {
		t.Fatalf("counter.Add(2) = %d, want 42", got)
	}
	if got := accumulator.Absorb(counter); got != 82 {
		t.Fatalf("second Absorb(counter) = %d, want 82", got)
	}
}

func TestIndependentLifecycles(t *testing.T) {
	counter, err := NewCounter(1)
	if err != nil {
		t.Fatal(err)
	}
	accumulator, err := NewAccumulator()
	if err != nil {
		t.Fatal(err)
	}

	accumulator.Close()
	accumulator.Close()
	counter.Close()
	counter.Close()
	if got := LiveObjects(); got != 0 {
		t.Fatalf("LiveObjects() = %d, want 0", got)
	}
}
