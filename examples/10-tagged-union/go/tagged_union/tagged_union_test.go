package tagged_union

import (
	"reflect"
	"testing"
)

func TestGeneratedTagAndCheckedPayloadAccessors(t *testing.T) {
	value, err := NewValue(42)
	if err != nil {
		t.Fatal(err)
	}
	defer value.Close()

	if got := value.Tag(); got != ValueTagInteger {
		t.Fatalf("Tag() = %v, want %v", got, ValueTagInteger)
	}
	if got, ok := value.AsInteger(); !ok || got != 42 {
		t.Fatalf("AsInteger() = (%d, %v), want (42, true)", got, ok)
	}
	if got, ok := value.AsFlag(); ok || got {
		t.Fatalf("AsFlag() on integer = (%v, %v), want (false, false)", got, ok)
	}

	value.SetFlag(true)
	if got, ok := value.AsFlag(); !ok || !got {
		t.Fatalf("AsFlag() = (%v, %v), want (true, true)", got, ok)
	}
	value.SetMode(ModePaused)
	if got, ok := value.AsMode(); !ok || got != ModePaused {
		t.Fatalf("AsMode() = (%v, %v), want (%v, true)", got, ok, ModePaused)
	}
}

func TestSliceIsCopiedAndBorrowedHandleHasAccessors(t *testing.T) {
	child, err := NewChild(17)
	if err != nil {
		t.Fatal(err)
	}
	defer child.Close()
	value, err := NewValue(1)
	if err != nil {
		t.Fatal(err)
	}
	defer value.Close()

	value.UsePresetSamples()
	first, ok := value.AsSamples()
	if !ok || !reflect.DeepEqual(first, []int16{3, 5, 8, 13}) {
		t.Fatalf("AsSamples() = (%v, %v)", first, ok)
	}
	first[0] = 99
	second, ok := value.AsSamples()
	if !ok || second[0] != 3 {
		t.Fatalf("AsSamples() did not return an independent copy: (%v, %v)", second, ok)
	}

	value.SetChild(child)
	borrowed := value.Borrow()
	if borrowed.Tag() != ValueTagChild {
		t.Fatalf("borrowed Tag() = %v, want %v", borrowed.Tag(), ValueTagChild)
	}
	childRef, ok := borrowed.AsChild()
	if !ok || childRef == nil {
		t.Fatalf("borrowed AsChild() = (%v, %v)", childRef, ok)
	}
}
