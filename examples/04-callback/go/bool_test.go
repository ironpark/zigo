package callback

import "testing"

// A `bool` in the callback signature is a plain Go `bool`; the shim widens it
// to `u8` on the wire and the handle constructor converts it back.
var _ Predicate = func(value int32, strict bool) bool { return strict }

func TestBoolCallbackRoundTrip(t *testing.T) {
	var seenStrict []bool
	predicate := func(value int32, strict bool) bool {
		seenStrict = append(seenStrict, strict)
		if strict {
			return value > 0
		}
		return value >= 0
	}
	if Filter(0, true, predicate) {
		t.Fatal("strict predicate accepted zero")
	}
	if !Filter(0, false, predicate) {
		t.Fatal("lenient predicate rejected zero")
	}
	if !Filter(3, true, predicate) {
		t.Fatal("strict predicate rejected three")
	}
	if len(seenStrict) != 3 || !seenStrict[0] || seenStrict[1] || !seenStrict[2] {
		t.Fatalf("strict flags did not round-trip: %v", seenStrict)
	}
}

// The native reducer takes its context first; Go sees the values only.
var _ Reducer = func(acc, value int32) int32 { return acc + value }

func TestUserdataFirstCallback(t *testing.T) {
	calls := 0
	sum := Reduce([]int32{1, 2, 3}, func(acc, value int32) int32 {
		calls++
		return acc + value
	})
	if sum != 6 || calls != 3 {
		t.Fatalf("reduce = %d after %d calls, want 6 after 3", sum, calls)
	}
}
