package scalar

import "testing"

func TestAdd(t *testing.T) {
	if got := Add(3, 7); got != 10 {
		t.Fatalf("Add(3, 7) = %d, want 10", got)
	}
}

func BenchmarkAddCgo(b *testing.B) {
	for i := 0; i < b.N; i++ {
		_ = Add(20, 22)
	}
}
