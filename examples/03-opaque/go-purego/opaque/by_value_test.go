package opaque

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func init() {
	_, file, _, _ := runtime.Caller(0)
	path := os.Getenv("ZIGO_LIBRARY_PATH")
	if path == "" {
		path = filepath.Join(filepath.Dir(file), "..", "..", "zig-out", "lib", DefaultLibraryName)
	}
	if err := LoadLibrary(path); err != nil {
		panic(err)
	}
}

func TestByValueOpaqueArgumentsCopyFromHandles(t *testing.T) {
	left, err := NewContext()
	if err != nil {
		t.Fatal(err)
	}
	defer left.Close()
	right, err := NewContext()
	if err != nil {
		t.Fatal(err)
	}
	defer right.Close()
	if err := left.SetTotal(7); err != nil {
		t.Fatal(err)
	}
	if err := right.SetTotal(5); err != nil {
		t.Fatal(err)
	}
	if got, err := left.AddCopy(4); err != nil || got != 11 {
		t.Fatalf("AddCopy(4) = (%d, %v), want (11, nil)", got, err)
	}
	if got, present, err := left.MaybeTotal(true); err != nil || !present || got != 7 {
		t.Fatalf("MaybeTotal(true) after AddCopy = (%d, %t, %v), want (7, true, nil)", got, present, err)
	}
	if got, err := SumCopies(0, left, right); err != nil || got != 12 {
		t.Fatalf("SumCopies(0, left, right) = (%d, %v), want (12, nil)", got, err)
	}
	closed, err := NewContext()
	if err != nil {
		t.Fatal(err)
	}
	if err := closed.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := closed.AddCopy(1); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("closed AddCopy(1) error = %v, want ErrInvalidHandle", err)
	}
	if _, err := SumCopies(0, left, closed); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("SumCopies with closed parameter error = %v, want ErrInvalidHandle", err)
	}
}
