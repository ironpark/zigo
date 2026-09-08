package materialized

import (
	"errors"
	"testing"
)

func TestOptionalMaterializedPresenceAndRelease(t *testing.T) {
	before := ReleasedBuffers()
	value, ok := OptionalSnapshot(false)
	if ok || value.Name != "" {
		t.Fatalf("absent snapshot = (%+v, %v)", value, ok)
	}
	if ReleasedBuffers() != before {
		t.Fatal("absent snapshot released a buffer")
	}
	value, ok = OptionalSnapshot(true)
	if !ok {
		t.Fatal("present snapshot reported absent")
	}
	checkProbe(t, value)
	if ReleasedBuffers() != before+1 {
		t.Fatal("present snapshot was not released exactly once")
	}
	for _, tc := range []struct{ present, empty bool }{{false, false}, {true, true}, {true, false}} {
		before := ReleasedBuffers()
		values, ok := OptionalBatch(tc.present, tc.empty)
		if ok != tc.present {
			t.Fatalf("batch presence = %v, want %v", ok, tc.present)
		}
		if !tc.present {
			if values != nil || ReleasedBuffers() != before {
				t.Fatal("absent batch allocated or released a buffer")
			}
		} else {
			if ReleasedBuffers() != before+1 {
				t.Fatal("present batch was not released exactly once")
			}
			if tc.empty {
				if len(values) != 0 {
					t.Fatal("present empty batch is not empty")
				}
			} else {
				if len(values) != 128 {
					t.Fatalf("batch size = %d", len(values))
				}
				checkProbe(t, values[127])
			}
		}
	}
}

func TestMaterializedIteratorExhaustionAndEarlyStop(t *testing.T) {
	for _, checked := range []bool{false, true} {
		for _, limit := range []uint32{0, 3} {
			cursor, err := NewCursor(limit, ^uint32(0))
			if err != nil {
				t.Fatal(err)
			}
			before := ReleasedBuffers()
			seen := uint32(0)
			sequence := cursor.All()
			if checked {
				sequence = cursor.Checked()
			}
			for value, err := range sequence {
				if err != nil {
					t.Fatal(err)
				}
				checkProbe(t, value)
				seen++
			}
			if seen != limit || ReleasedBuffers() != before+limit {
				t.Fatalf("exhaustion: seen=%d released=%d", seen, ReleasedBuffers()-before)
			}
			if _, ok, err := cursor.NextChecked(); err != nil || ok {
				t.Fatalf("exhausted NextChecked = (%v, %v)", ok, err)
			}
			if ReleasedBuffers() != before+limit {
				t.Fatal("exhaustion released an absent buffer")
			}
			if err := cursor.Close(); err != nil {
				t.Fatal(err)
			}
		}
	}
	cursor, err := NewCursor(3, ^uint32(0))
	if err != nil {
		t.Fatal(err)
	}
	defer cursor.Close()
	before := ReleasedBuffers()
	for value, err := range cursor.All() {
		if err != nil {
			t.Fatal(err)
		}
		checkProbe(t, value)
		break
	}
	count, err := cursor.Count()
	if err != nil || count != 1 || ReleasedBuffers() != before+1 {
		t.Fatalf("early stop: count=%d err=%v released=%d", count, err, ReleasedBuffers()-before)
	}
}

func TestMaterializedIteratorYieldsErrorOnce(t *testing.T) {
	for _, failAt := range []uint32{0, 1} {
		cursor, err := NewCursor(3, failAt)
		if err != nil {
			t.Fatal(err)
		}
		before := ReleasedBuffers()
		seen, failures := uint32(0), 0
		for value, err := range cursor.Checked() {
			if err != nil {
				if !errors.Is(err, ErrInvalid) || value.Name != "" {
					t.Fatalf("error yield = (%+v, %v)", value, err)
				}
				failures++
			} else {
				checkProbe(t, value)
				seen++
			}
		}
		if failures != 1 || seen != failAt || ReleasedBuffers() != before+failAt {
			t.Fatalf("error sequence: values=%d errors=%d released=%d", seen, failures, ReleasedBuffers()-before)
		}
		if err := cursor.Close(); err != nil {
			t.Fatal(err)
		}
	}
}

func TestOptionalMaterializedBatchErrors(t *testing.T) {
	before := ReleasedBuffers()
	values, ok, err := OptionalBatchChecked(true, false, true)
	if values != nil || ok || !errors.Is(err, ErrInvalid) {
		t.Fatalf("failed batch = (%v, %v, %v)", values, ok, err)
	}
	if ReleasedBuffers() != before {
		t.Fatal("failed batch released a buffer")
	}
	values, ok, err = OptionalBatchChecked(false, false, false)
	if values != nil || ok || err != nil {
		t.Fatalf("absent batch = (%v, %v, %v)", values, ok, err)
	}
	if ReleasedBuffers() != before {
		t.Fatal("absent checked batch released a buffer")
	}
	for _, empty := range []bool{false, true} {
		values, ok, err = OptionalBatchChecked(true, empty, false)
		if !ok || err != nil {
			t.Fatalf("present batch = (%v, %v)", ok, err)
		}
		if empty {
			if len(values) != 0 {
				t.Fatal("present empty checked batch is not empty")
			}
		} else {
			checkProbe(t, values[127])
		}
		before++
		if ReleasedBuffers() != before {
			t.Fatal("checked batch was not released exactly once")
		}
	}
}
