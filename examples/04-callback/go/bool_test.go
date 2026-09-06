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
