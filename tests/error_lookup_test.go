package pipeline

import (
	"errors"
	"strconv"
	"testing"
)

func TestErrorLookup(t *testing.T) {
	for code, name := range map[int32]string{1: "OutOfMemory", 2: "InvalidName", 3: "EmptyInput", 4: "Disabled", 5: "CallbackPanicked", 0: "Unknown(0)", 6: "Unknown(6)", -1: "Unknown(-1)", 2147483647: "Unknown(2147483647)"} {
		got := zigoErrorForCode("operation", code).(*Error)
		if got.Code != code || got.Name != name || got.Operation != "operation" {
			t.Fatalf("code %d: %#v", code, got)
		}
	}
	first := zigoErrorForCode("first", 1)
	second := zigoErrorForCode("second", 1)
	if !errors.Is(first, ErrOutOfMemory) || first == second || ErrOutOfMemory.Operation != "" {
		t.Fatal("error identity or context changed")
	}
	if first.(*Error).Operation != "first" {
		t.Fatal("operation overwritten")
	}
	panicErr, ok := zigoErrorForCode("panic", -256).(*NativePanicError)
	if !ok || panicErr.Operation != "panic" || panicErr.Message != "test panic" {
		t.Fatalf("panic: %#v", panicErr)
	}
}

var errorSink error

func errorSwitch(operation string, code int32) error {
	if code <= -256 {
		return zigoErrorForCode(operation, code)
	}
	switch code {
	case 1:
		return &Error{Code: 1, Name: "OutOfMemory", Operation: operation}
	case 2:
		return &Error{Code: 2, Name: "InvalidName", Operation: operation}
	case 3:
		return &Error{Code: 3, Name: "EmptyInput", Operation: operation}
	case 4:
		return &Error{Code: 4, Name: "Disabled", Operation: operation}
	case 5:
		return &Error{Code: 5, Name: "CallbackPanicked", Operation: operation}
	}
	return &Error{Code: code, Name: "Unknown(" + strconv.Itoa(int(code)) + ")", Operation: operation}
}

func BenchmarkErrorLookup(b *testing.B) {
	b.Run("array", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			errorSink = zigoErrorForCode("operation", int32(i%5)+1)
		}
	})
	b.Run("switch", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			errorSink = errorSwitch("operation", int32(i%5)+1)
		}
	})
}
