package opaque

import "testing"

func TestOpaqueLifecycle(t *testing.T) {
	for range 100 {
		context, err := NewContext()
		if err != nil {
			t.Fatal(err)
		}
		if got := context.Add(3); got != 3 {
			t.Fatalf("Add() = %d, want 3", got)
		}
		context.Close()
		context.Close()
	}
	if got := LiveBytes(); got != 0 {
		t.Fatalf("LiveBytes() = %d, want 0", got)
	}
}
