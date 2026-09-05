package opaque_test

import (
	"errors"
	"testing"

	"example.com/zigo/opaque/opaque"
)

func TestContextAllRangesUntilExhausted(t *testing.T) {
	counter, err := opaque.NewContext()
	if err != nil {
		t.Fatal(err)
	}
	defer counter.Close()
	if err := counter.SetTotal(3); err != nil {
		t.Fatal(err)
	}

	var seen []int64
	for value, err := range counter.All() {
		if err != nil {
			t.Fatal(err)
		}
		seen = append(seen, value)
	}
	if len(seen) != 3 || seen[0] != 1 || seen[2] != 3 {
		t.Fatalf("All() yielded %v, want [1 2 3]", seen)
	}

	// A second pass starts where the first stopped: the sequence is a view of
	// native state, so rewinding is the library's job.
	for range counter.All() {
		t.Fatal("All() yielded after exhaustion")
	}
	if err := counter.Rewind(); err != nil {
		t.Fatal(err)
	}
	var count int
	for value, err := range counter.All() {
		if err != nil {
			t.Fatal(err)
		}
		count++
		if value == 2 {
			break
		}
	}
	if count != 2 {
		t.Fatalf("break left count = %d, want 2", count)
	}
}

func TestContextCheckedYieldsErrorOnce(t *testing.T) {
	counter, err := opaque.NewContext()
	if err != nil {
		t.Fatal(err)
	}
	defer counter.Close()
	if err := counter.SetTotal(-1); err != nil {
		t.Fatal(err)
	}

	var yields int
	for value, err := range counter.Checked() {
		yields++
		if value != 0 || !errors.Is(err, opaque.ErrNegativeTotal) {
			t.Fatalf("Checked() yielded (%d, %v), want (0, ErrNegativeTotal)", value, err)
		}
	}
	if yields != 1 {
		t.Fatalf("Checked() yielded %d times, want 1", yields)
	}
}

func TestContextAllReportsClosedHandle(t *testing.T) {
	counter, err := opaque.NewContext()
	if err != nil {
		t.Fatal(err)
	}
	if err := counter.Close(); err != nil {
		t.Fatal(err)
	}
	for _, err := range counter.All() {
		if !errors.Is(err, opaque.ErrInvalidHandle) {
			t.Fatalf("All() on a closed handle yielded %v", err)
		}
		return
	}
	t.Fatal("All() on a closed handle yielded nothing")
}
