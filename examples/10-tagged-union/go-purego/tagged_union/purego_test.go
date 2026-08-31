package tagged_union

import (
	"errors"
	"os"
	"strings"
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
	// The message is read out of native memory, so assert its text and not
	// just the code: a broken pointer walk would still classify correctly.
	// A Zig panic classifies the same way whether it came from a projection
	// status or from an error-returning call.
	if err := PanicError(); !errors.Is(err, ErrNativePanic) {
		t.Fatalf("panic translation = %v", err)
	} else if !strings.Contains(err.Error(), "purego panic translation") {
		t.Fatalf("panic message = %q, want the native text", err.Error())
	}

	value, err := NewValue(42)
	if err != nil {
		t.Fatal(err)
	}
	defer value.Close()
	if got := must(value.Tag()); got != ValueTagInteger {
		t.Fatalf("tag = %v", got)
	}
	if got, ok := must2(value.AsInteger()); !ok || got != 42 {
		t.Fatalf("integer = %d, %v", got, ok)
	}
	if err := value.SetFlag(true); err != nil {
		t.Fatal(err)
	}
	if got, ok := must2(value.AsFlag()); !ok || !got {
		t.Fatalf("flag = %v, %v", got, ok)
	}
	if err := value.UseEmptySamples(); err != nil {
		t.Fatal(err)
	}
	if got, ok := must2(value.AsSamples()); !ok || len(got) != 0 {
		t.Fatalf("empty samples = %v, %v", got, ok)
	}

	assertSignalSnapshots(t)
	assertValueVariants(t)
	assertSignalVariants(t)
}

// must unwraps a generated call whose only failure mode in these tests would be
// a nil or closed handle, which the tests establish is not the case.
func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

// must2 is must for the projection accessors, which also report whether the
// variant is active.
func must2[T any](value T, matched bool, err error) (T, bool) {
	if err != nil {
		panic(err)
	}
	return value, matched
}
