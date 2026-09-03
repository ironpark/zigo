package callback

import (
	"sync/atomic"
	"testing"
)

func TestNestedFieldAccessors(t *testing.T) {
	context, err := NewCallbackContext(func(value int32) (int32, error) { return value, nil })
	if err != nil {
		t.Fatal(err)
	}
	defer context.Close()
	if err := context.SetRunCount(41); err != nil {
		t.Fatal(err)
	}
	if _, err := context.Run(7); err != nil {
		t.Fatal(err)
	}
	got, err := context.RunCount()
	if err != nil {
		t.Fatal(err)
	}
	if got != 42 {
		t.Fatalf("RunCount() = %d, want 42", got)
	}
}

func TestSharedAtomicParameter(t *testing.T) {
	var counter atomic.Uint64
	counter.Store(40)
	if got := IncrementShared(&counter, 2); got != 42 {
		t.Fatalf("IncrementShared() = %d, want 42", got)
	}
	if got := counter.Load(); got != 42 {
		t.Fatalf("counter.Load() = %d, want 42", got)
	}
	var signed atomic.Int32
	signed.Store(-7)
	if got := ReadShared(&signed); got != -7 {
		t.Fatalf("ReadShared() = %d, want -7", got)
	}
}
