package errors

import (
	stderrors "errors"
	"strings"
	"testing"

	"example.com/zigo/errors/support/ffi"
)

func TestDivideByZero(t *testing.T) {
	_, err := Divide(1, 0)
	if !stderrors.Is(err, ErrDivideByZero) {
		t.Fatalf("Divide(1, 0) error = %v, want ErrDivideByZero", err)
	}
}

func TestSum(t *testing.T) {
	if got := Sum([]float64{1, 2, 3}); got != 6 {
		t.Fatalf("Sum = %v, want 6", got)
	}
	if got := Sum(nil); got != 0 {
		t.Fatalf("Sum(nil) = %v, want 0", got)
	}
}

func TestFormat(t *testing.T) {
	if got := NormalizeFormat(FormatFlac); got != FormatFlac || got.String() != "flac" {
		t.Fatalf("NormalizeFormat(FormatFlac) = %v", got)
	}
}

func TestCodepointWidth(t *testing.T) {
	if got, err := CodepointWidth(0x1100); err != nil || got != 2 {
		t.Fatalf("CodepointWidth(0x1100) = %d, %v, want 2, nil", got, err)
	}
	if _, err := CodepointWidth(0x1F); !stderrors.Is(err, ErrNotPrintable) {
		t.Fatalf("CodepointWidth(0x1F) error = %v, want ErrNotPrintable", err)
	}
}

// A `u21` argument travels in a `uint32`, so Go can hand over a value the Zig
// type cannot hold. The generated function checks the range itself and returns
// a RangeError; the native library is never called, which is why the panic
// message left behind by any earlier call is still whatever it was.
func TestCodepointWidthOutOfRange(t *testing.T) {
	_, err := CodepointWidth(1 << 21)
	if !stderrors.Is(err, ErrOutOfRange) {
		t.Fatalf("CodepointWidth(1<<21) error = %v, want ErrOutOfRange", err)
	}
	var rangeErr *RangeError
	if !stderrors.As(err, &rangeErr) || rangeErr.Parameter != "cp" || rangeErr.Type != "u21" {
		t.Fatalf("CodepointWidth(1<<21) error = %#v, want a RangeError naming cp and u21", err)
	}
	if !strings.Contains(err.Error(), "out of range for u21") {
		t.Fatalf("CodepointWidth(1<<21) error = %q, want it to name the range", err)
	}
	if message := ffi.LastErrorMessage(); message != "" {
		t.Fatalf("LastErrorMessage() = %q, want empty: no native call was made", message)
	}
}
