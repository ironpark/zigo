package scalar

import "testing"

func TestAdd(t *testing.T) {
	if got := Add(3, 7); got != 10 {
		t.Fatalf("Add(3, 7) = %d, want 10", got)
	}
}
