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

func TestNamesAndUTF8(t *testing.T) {
	const text = "안녕, Zig와 Go"
	if got := Echo(text); got != text {
		t.Fatalf("Echo() = %q, want %q", got, text)
	}
	if got := Fallback(21); got != 42 {
		t.Fatalf("Fallback() = %d, want 42", got)
	}
}
