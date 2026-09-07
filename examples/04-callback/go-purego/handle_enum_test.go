package callback

import "testing"

// A handle pointer, an enum, and a `bool` in one callback signature. The
// handle is a borrowed view the callback may call methods on; a null pointer
// arrives as a nil handle.
var _ Inspector = func(context *CallbackContext, level Level, strict bool) int32 { return 0 }

func TestHandleAndEnumCallbackParameters(t *testing.T) {
	context, err := NewCallbackContext(func(value int32) (int32, error) { return value, nil })
	if err != nil {
		t.Fatal(err)
	}
	defer context.Close()
	if err := context.SetRunCount(5); err != nil {
		t.Fatal(err)
	}

	var seenLevels []Level
	var seenStrict []bool
	inspector := func(inspected *CallbackContext, level Level, strict bool) int32 {
		seenLevels = append(seenLevels, level)
		seenStrict = append(seenStrict, strict)
		if inspected == nil {
			return -1
		}
		runs, err := inspected.RunCount()
		if err != nil {
			t.Errorf("RunCount inside callback: %v", err)
			return -2
		}
		return int32(runs)
	}

	got, err := Inspect(context, LevelWarn, true, inspector)
	if err != nil {
		t.Fatal(err)
	}
	if got != 5 {
		t.Fatalf("Inspect with a handle = %d, want the run count 5", got)
	}
	got, err = Inspect(nil, LevelErr, false, inspector)
	if err != nil {
		t.Fatal(err)
	}
	if got != -1 {
		t.Fatalf("Inspect with nil = %d, want -1", got)
	}
	if len(seenLevels) != 2 || seenLevels[0] != LevelWarn || seenLevels[1] != LevelErr {
		t.Fatalf("levels did not round-trip: %v", seenLevels)
	}
	if len(seenStrict) != 2 || !seenStrict[0] || seenStrict[1] {
		t.Fatalf("strict flags did not round-trip: %v", seenStrict)
	}
}
