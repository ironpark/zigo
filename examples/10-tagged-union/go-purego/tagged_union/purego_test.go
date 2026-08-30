package tagged_union

import (
	"errors"
	"os"
	"testing"
)

func TestPuregoTaggedUnion(t *testing.T) {
	library := os.Getenv("ZIGO_TEST_LIBRARY")
	if library == "" {
		t.Skip("ZIGO_TEST_LIBRARY is not set")
	}
	if err := LoadLibrary("/definitely/missing/zigo-library"); err == nil {
		t.Fatal("missing library unexpectedly loaded")
	} else {
		var libraryErr *LibraryError
		if !errors.As(err, &libraryErr) {
			t.Fatalf("error type = %T, want *LibraryError", err)
		}
	}
	if LibraryLoaded() {
		t.Fatal("failed load partially published bindings")
	}
	if wrong := os.Getenv("ZIGO_TEST_WRONG_LIBRARY"); wrong != "" {
		err := LoadLibrary(wrong)
		var libraryErr *LibraryError
		if !errors.As(err, &libraryErr) || libraryErr.Symbol == "" {
			t.Fatalf("missing-symbol error = %#v", err)
		}
		if LibraryLoaded() {
			t.Fatal("missing symbol partially published bindings")
		}
	}
	if err := LoadLibrary(library); err != nil {
		t.Fatal(err)
	}
	if err := LoadLibrary(library); err != nil {
		t.Fatalf("repeat load: %v", err)
	}
	if !LibraryLoaded() {
		t.Fatal("library not marked loaded")
	}
	if got := Sum(nil); got != 0 {
		t.Fatalf("empty sum = %v", got)
	}
	if got := Sum([]float64{1.25, 2.75}); got != 4 {
		t.Fatalf("sum = %v", got)
	}
	if _, err := Divide(1, 0); !errors.Is(err, ErrDivideByZero) {
		t.Fatalf("divide error = %v", err)
	}
	if err := PanicError(); !errors.Is(err, ErrPanicCaught) {
		t.Fatalf("panic translation = %v", err)
	}

	value, err := NewValue(42)
	if err != nil {
		t.Fatal(err)
	}
	defer value.Close()
	if got := value.Tag(); got != ValueTagInteger {
		t.Fatalf("tag = %v", got)
	}
	if got, ok := value.AsInteger(); !ok || got != 42 {
		t.Fatalf("integer = %d, %v", got, ok)
	}
	value.SetFlag(true)
	if got, ok := value.AsFlag(); !ok || !got {
		t.Fatalf("flag = %v, %v", got, ok)
	}
	value.UseEmptySamples()
	if got, ok := value.AsSamples(); !ok || len(got) != 0 {
		t.Fatalf("empty samples = %v, %v", got, ok)
	}
}
