package tagged_union

import (
	"errors"
	"testing"
)

// assertSignalSnapshots exercises the value snapshot representation: one
// native call must carry the active tag and its payload back together.
func assertSignalSnapshots(t *testing.T) {
	t.Helper()

	signal, err := NewSignal(7)
	if err != nil {
		t.Fatal(err)
	}
	defer signal.Close()

	// A single Snapshot() call answers both "which variant?" and "what is the
	// payload?"; the projection accessors need one call each.
	snapshot := must(signal.Snapshot())
	if got := snapshot.Tag(); got != SignalTagTicks {
		t.Fatalf("Tag() = %v, want %v", got, SignalTagTicks)
	}
	if got, ok := snapshot.Ticks(); !ok || got != 7 {
		t.Fatalf("Ticks() = (%d, %v), want (7, true)", got, ok)
	}
	if _, ok := snapshot.Level(); ok {
		t.Fatal("Level() reported active on a ticks snapshot")
	}

	if err := signal.SetLevel(1.5); err != nil {
		t.Fatal(err)
	}
	if snapshot, err := signal.Snapshot(); err != nil {
		t.Fatal(err)
	} else if got, ok := snapshot.Level(); !ok || got != 1.5 {
		t.Fatalf("Level() = (%v, %v), want (1.5, true)", got, ok)
	}

	if err := signal.SetOffset(-3); err != nil {
		t.Fatal(err)
	}
	if got, ok := must(signal.Snapshot()).Offset(); !ok || got != -3 {
		t.Fatalf("Offset() = (%d, %v), want (-3, true)", got, ok)
	}

	if err := signal.SetMode(ModeActive); err != nil {
		t.Fatal(err)
	}
	if got, ok := must(signal.Snapshot()).Mode(); !ok || got != ModeActive {
		t.Fatalf("Mode() = (%v, %v), want (%v, true)", got, ok, ModeActive)
	}

	// bool crosses the C ABI as uint8 like everywhere else in zigo; public Go
	// restores it.
	if err := signal.SetActive(true); err != nil {
		t.Fatal(err)
	}
	if got, ok := must(signal.Snapshot()).Active(); !ok || !got {
		t.Fatalf("Active() = (%v, %v), want (true, true)", got, ok)
	}

	// A void variant carries no payload, so the tag alone reports it.
	if err := signal.SetIdle(); err != nil {
		t.Fatal(err)
	}
	idle := must(signal.Snapshot())
	if got := idle.Tag(); got != SignalTagIdle {
		t.Fatalf("Tag() = %v, want %v", got, SignalTagIdle)
	}
	if _, ok := idle.Ticks(); ok {
		t.Fatal("Ticks() reported active on an idle snapshot")
	}

	// The snapshot API is additive: the projections still work.
	if err := signal.SetTicks(11); err != nil {
		t.Fatal(err)
	}
	if got, ok := must2(signal.AsTicks()); !ok || got != 11 {
		t.Fatalf("AsTicks() = (%d, %v), want (11, true)", got, ok)
	}

	// A closed handle reports a lifecycle error instead of reaching Zig.
	signal.Close()
	if _, err := signal.Snapshot(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Snapshot() after Close = %v, want ErrInvalidHandle", err)
	}
}
