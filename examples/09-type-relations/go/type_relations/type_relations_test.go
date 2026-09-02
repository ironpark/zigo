package type_relations

import (
	"io"
	"testing"
)

// Generated handles close like any other Go resource.
var (
	_ io.Closer = (*Counter)(nil)
	_ io.Closer = (*Accumulator)(nil)
)

// must unwraps a generated call whose only failure mode here would be a nil or
// closed handle.
func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

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

	if got := must(accumulator.Absorb(counter)); got != 40 {
		t.Fatalf("Absorb(counter) = %d, want 40", got)
	}
	if got := must(counter.Add(2)); got != 42 {
		t.Fatalf("counter.Add(2) = %d, want 42", got)
	}
	if got := must(accumulator.Absorb(counter)); got != 82 {
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

// The binding reaches these through `root.text.runWidth` and
// `root.text.unicode.codepointWidth`, so the nested namespaces cross the
// boundary without a hand-written flattening facade in Zig.
func TestNestedNamespaces(t *testing.T) {
	if got := CodepointWidth(0x1100); got != 2 {
		t.Fatalf("CodepointWidth(0x1100) = %d, want 2", got)
	}
	if got := RunWidth(0x1100, 'a'); got != 3 {
		t.Fatalf("RunWidth(0x1100, 'a') = %d, want 3", got)
	}
}
