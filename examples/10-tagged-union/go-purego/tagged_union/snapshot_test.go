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
	snapshot := signal.Snapshot()
	if got := snapshot.Tag(); got != SignalTagTicks {
		t.Fatalf("Tag() = %v, want %v", got, SignalTagTicks)
	}
	if got, ok := snapshot.Ticks(); !ok || got != 7 {
		t.Fatalf("Ticks() = (%d, %v), want (7, true)", got, ok)
	}
	if _, ok := snapshot.Level(); ok {
		t.Fatal("Level() reported active on a ticks snapshot")
	}

	signal.SetLevel(1.5)
	if snapshot, err := signal.TrySnapshot(); err != nil {
		t.Fatal(err)
	} else if got, ok := snapshot.Level(); !ok || got != 1.5 {
		t.Fatalf("Level() = (%v, %v), want (1.5, true)", got, ok)
	}

	signal.SetOffset(-3)
	if got, ok := signal.Snapshot().Offset(); !ok || got != -3 {
		t.Fatalf("Offset() = (%d, %v), want (-3, true)", got, ok)
	}

	signal.SetMode(ModeActive)
	if got, ok := signal.Snapshot().Mode(); !ok || got != ModeActive {
		t.Fatalf("Mode() = (%v, %v), want (%v, true)", got, ok, ModeActive)
	}

	// bool crosses the C ABI as uint8 like everywhere else in zigo; public Go
	// restores it.
	signal.SetActive(true)
	if got, ok := signal.Snapshot().Active(); !ok || !got {
		t.Fatalf("Active() = (%v, %v), want (true, true)", got, ok)
	}

	// A void variant carries no payload, so the tag alone reports it.
	signal.SetIdle()
	idle := signal.Snapshot()
	if got := idle.Tag(); got != SignalTagIdle {
		t.Fatalf("Tag() = %v, want %v", got, SignalTagIdle)
	}
	if _, ok := idle.Ticks(); ok {
		t.Fatal("Ticks() reported active on an idle snapshot")
	}

	// The snapshot API is additive: the projections still work.
	signal.SetTicks(11)
	if got, ok := signal.AsTicks(); !ok || got != 11 {
		t.Fatalf("AsTicks() = (%d, %v), want (11, true)", got, ok)
	}

	// A closed handle reports a lifecycle error instead of reaching Zig.
	signal.Close()
	if _, err := signal.TrySnapshot(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("TrySnapshot() after Close = %v, want ErrInvalidHandle", err)
	}
}
