package opaque

import (
	"errors"
	"io"
	"testing"
)

// A generated handle closes like any other Go resource.
var _ io.Closer = (*Context)(nil)

// must unwraps a generated call whose only failure mode here would be a nil or
// closed handle.
func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

func TestOpaqueLifecycle(t *testing.T) {
	for range 100 {
		context, err := NewContext()
		if err != nil {
			t.Fatal(err)
		}
		if got := must(context.Add(3)); got != 3 {
			t.Fatalf("Add() = %d, want 3", got)
		}
		if got, present, err := context.MaybeTotal(true); err != nil || !present || got != 3 {
			t.Fatalf("MaybeTotal(true) = (%d, %t, %v), want (3, true, nil)", got, present, err)
		}
		if got, present, err := context.MaybeTotal(false); err != nil || present || got != 0 {
			t.Fatalf("MaybeTotal(false) = (%d, %t, %v), want (0, false, nil)", got, present, err)
		}
		if err := context.SetTotal(7); err != nil {
			t.Fatal(err)
		}
		if got, present, err := context.MaybeTotal(true); err != nil || !present || got != 7 {
			t.Fatalf("MaybeTotal(true) after SetTotal = (%d, %t, %v), want (7, true, nil)", got, present, err)
		}
		context.Close()
		if got, present, err := context.MaybeTotal(true); err == nil || present || got != 0 {
			t.Fatalf("closed MaybeTotal(true) = (%d, %t, %v), want (0, false, error)", got, present, err)
		}
		context.Close()
	}
	if got := LiveBytes(); got != 0 {
		t.Fatalf("LiveBytes() = %d, want 0", got)
	}
}

func TestBorrowedContextViewIsInvalidatedByParentClose(t *testing.T) {
	context, err := NewContext()
	if err != nil {
		t.Fatal(err)
	}
	if err := context.SetTotal(19); err != nil {
		t.Fatal(err)
	}
	view, err := context.BorrowView()
	if err != nil {
		t.Fatal(err)
	}
	if got, err := view.Total(); err != nil || got != 19 {
		t.Fatalf("view.Total() = (%d, %v), want (19, nil)", got, err)
	}
	if err := context.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := view.Total(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("view.Total() after parent Close = %v, want ErrInvalidHandle", err)
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
