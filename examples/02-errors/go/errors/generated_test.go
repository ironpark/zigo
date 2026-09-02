package errors

import (
	stderrors "errors"
	"strings"
	"testing"
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
// type cannot hold. The shim rejects it rather than truncating, and the panic
// bridge reports that as a native panic.
func TestCodepointWidthOutOfRange(t *testing.T) {
	_, err := CodepointWidth(1 << 21)
	if !stderrors.Is(err, ErrNativePanic) {
		t.Fatalf("CodepointWidth(1<<21) error = %v, want ErrNativePanic", err)
	}
	if !strings.Contains(err.Error(), "out of range for u21") {
		t.Fatalf("CodepointWidth(1<<21) error = %q, want it to name the range", err)
	}
}
