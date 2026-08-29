package errors

import (
	stderrors "errors"
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
