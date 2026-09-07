package tagged_union

import "testing"

func TestEnumkit(t *testing.T) {
	values := ModeValues()
	want := []Mode{ModeIdle, ModeActive, ModePaused}
	if len(values) != len(want) {
		t.Fatalf("values: %v", values)
	}
	for i, v := range values {
		if v != want[i] || !v.IsKnown() {
			t.Fatalf("value %d: %v", i, v)
		}
	}
	values[0] = Mode(255)
	if ModeValues()[0] != ModeIdle {
		t.Fatal("returned slices share storage")
	}
	if Mode(255).IsKnown() {
		t.Fatal("unknown value reported as known")
	}
}
