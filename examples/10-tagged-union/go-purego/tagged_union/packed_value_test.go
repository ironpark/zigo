package tagged_union

import "testing"

func TestPackedValueRoundTrips(t *testing.T) {
	want := RGB{R: 1, G: 2, B: 3}
	if got := want.Backing(); got != 0x030201 {
		t.Fatalf("Backing() = %#x, want %#x", got, uint32(0x030201))
	}
	if got := RGBFromBacking(want.Backing()); got != want {
		t.Fatalf("RGBFromBacking() = %#v, want %#v", got, want)
	}
}

func assertPackedValueCalls(t *testing.T) {
	want := RGB{R: 1, G: 2, B: 3}
	if got := EchoRgb(want); got != want {
		t.Fatalf("EchoRGB() = %#v, want %#v", got, want)
	}
	if got, ok := MaybeRgb(true); !ok || got != (RGB{R: 9, G: 10, B: 11}) {
		t.Fatalf("MaybeRGB(true) = (%#v, %v)", got, ok)
	}
	if _, ok := MaybeRgb(false); ok {
		t.Fatal("MaybeRGB(false) reported a value")
	}
	if got, err := CheckedRgb(true); err != nil || got != (RGB{R: 12, G: 13, B: 14}) {
		t.Fatalf("CheckedRGB(true) = (%#v, %v)", got, err)
	}
	if _, err := CheckedRgb(false); err == nil {
		t.Fatal("CheckedRGB(false) returned nil error")
	}
	flags := Flags{Enabled: true, Level: 3, Mode: ModePaused}
	record := ColorRecord{Flags: flags, Code: 17}
	if got := EchoColorRecord(record); got != record {
		t.Fatalf("EchoColorRecord() = %#v, want %#v", got, record)
	}
	if got := FlattenFlags(flags); got != flags {
		t.Fatalf("FlattenFlags() = %#v, want %#v", got, flags)
	}
	palette, err := NewPalette(flags)
	if err != nil {
		t.Fatalf("NewPalette() error = %v", err)
	}
	defer palette.Close()
	if got, err := palette.Flags(); err != nil || got != flags {
		t.Fatalf("Palette.Flags() = (%#v, %v)", got, err)
	}
	updated := Flags{Enabled: false, Level: 6, Mode: ModeActive}
	if err := palette.SetFlags(updated); err != nil {
		t.Fatalf("Palette.SetFlags() error = %v", err)
	}
	if got, err := palette.Flags(); err != nil || got != updated {
		t.Fatalf("Palette.Flags() after set = (%#v, %v)", got, err)
	}
	var observed Flags
	VisitFlags(func(value Flags) { observed = value })
	if wantObserved := (Flags{Enabled: true, Level: 5, Mode: ModePaused}); observed != wantObserved {
		t.Fatalf("VisitFlags callback = %#v, want %#v", observed, wantObserved)
	}
}
