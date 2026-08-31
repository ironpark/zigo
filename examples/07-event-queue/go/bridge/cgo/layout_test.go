package cgo_test

import (
	"testing"
	"unsafe"

	"example.com/zigo/event-queue/bridge/cgo"
	"example.com/zigo/event-queue/bridge/cgo/cheader"
)

// The Go mirrors are only correct if they reproduce the C header exactly. cgo
// converts member by member and does not depend on that, but purego hands the
// mirror's address straight to the native call, where a drift would be a silent
// misread. Comparing against the real C struct catches it here instead.
func TestStructMirrorsMatchTheCHeader(t *testing.T) {
	if got := unsafe.Sizeof(cgo.StatsData{}); got != cheader.StatsSize {
		t.Fatalf("sizeof(StatsData) = %d, want %d", got, cheader.StatsSize)
	}
	statsOffsets := map[string]uintptr{
		"len":       unsafe.Offsetof(cgo.StatsData{}.Len),
		"capacity":  unsafe.Offsetof(cgo.StatsData{}.Capacity),
		"dropped":   unsafe.Offsetof(cgo.StatsData{}.Dropped),
		"processed": unsafe.Offsetof(cgo.StatsData{}.Processed),
		"policy":    unsafe.Offsetof(cgo.StatsData{}.Policy),
		"saturated": unsafe.Offsetof(cgo.StatsData{}.Saturated),
	}
	for name, want := range cheader.StatsOffsets {
		if got := statsOffsets[name]; got != want {
			t.Fatalf("StatsData.%s offset = %d, want %d", name, got, want)
		}
	}

	if got := unsafe.Sizeof(cgo.LimitsData{}); got != cheader.LimitsSize {
		t.Fatalf("sizeof(LimitsData) = %d, want %d", got, cheader.LimitsSize)
	}
	limitsOffsets := map[string]uintptr{
		"capacity": unsafe.Offsetof(cgo.LimitsData{}.Capacity),
		"policy":   unsafe.Offsetof(cgo.LimitsData{}.Policy),
	}
	for name, want := range cheader.LimitsOffsets {
		if got := limitsOffsets[name]; got != want {
			t.Fatalf("LimitsData.%s offset = %d, want %d", name, got, want)
		}
	}
}
