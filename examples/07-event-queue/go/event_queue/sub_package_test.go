package event_queue

import (
	"errors"
	"testing"

	eventtypes "example.com/zigo/event-queue/event_queue/types"
)

func TestDefaultPackageAcceptsSubPackageHandleAndStruct(t *testing.T) {
	ticker, err := eventtypes.NewTicker(4)
	if err != nil {
		t.Fatal(err)
	}
	defer ticker.Close()

	if _, err := ticker.Advance(5); err != nil {
		t.Fatal(err)
	}
	info, err := InspectTicker(eventtypes.TickerInfo{Ticks: 7}, ticker)
	if err != nil {
		t.Fatal(err)
	}
	if info.Interval != 4 || info.Ticks != 12 {
		t.Fatalf("InspectTicker() = %+v, want {Interval:4 Ticks:12}", info)
	}
}

func TestSubPackageSentinelsShareIdentity(t *testing.T) {
	_, err := eventtypes.NewTicker(0)
	if !errors.Is(err, eventtypes.ErrInvalidInterval) || !errors.Is(err, ErrInvalidInterval) {
		t.Fatalf("NewTicker(0) = %v, want both package sentinels", err)
	}
}
