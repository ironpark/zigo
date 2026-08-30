package telemetry_hub

import (
	"errors"
	"fmt"
	"math"
	"sync"
	"testing"
)

var _ TelemetryHubObserver = func(uint64, float64) int32 { return 0 }

func TestConfigurationAndEnumSurface(t *testing.T) {
	if ModeScaled.String() != "scaled" || OverflowPolicyDropOldest.String() != "drop_oldest" || SeverityCritical.String() != "critical" {
		t.Fatal("generated enum names do not match Zig tags")
	}
	hub, err := NewTelemetryHub("서울 관측소", 4, ModeRaw, OverflowPolicyReject, func(uint64, float64) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer hub.Close()

	if hub.Name() != "서울 관측소" || hub.Capacity() != 4 || !hub.Enabled() || !hub.IsEmpty() || hub.IsFull() {
		t.Fatalf("unexpected initial state: name=%q capacity=%d enabled=%v empty=%v full=%v", hub.Name(), hub.Capacity(), hub.Enabled(), hub.IsEmpty(), hub.IsFull())
	}
	if err := hub.Rename("edge/α-02"); err != nil || hub.Name() != "edge/α-02" {
		t.Fatalf("Rename() state = %q, error = %v", hub.Name(), err)
	}
	if previous := hub.SetMode(ModeScaled); previous != ModeRaw || hub.Mode() != ModeScaled {
		t.Fatalf("SetMode() previous=%v current=%v", previous, hub.Mode())
	}
	if previous := hub.SetOverflowPolicy(OverflowPolicyDropOldest); previous != OverflowPolicyReject || hub.OverflowPolicy() != OverflowPolicyDropOldest {
		t.Fatalf("SetOverflowPolicy() previous=%v current=%v", previous, hub.OverflowPolicy())
	}
	if previous := hub.SetEnabled(false); !previous || hub.Enabled() {
		t.Fatalf("SetEnabled(false) previous=%v current=%v", previous, hub.Enabled())
	}
	hub.SetEnabled(true)
	if err := hub.SetThreshold(-12.5); err != nil || hub.Threshold() != -12.5 {
		t.Fatalf("SetThreshold() value=%v error=%v", hub.Threshold(), err)
	}
	if err := hub.SetScaleFactor(2.5); err != nil || hub.ScaleFactor() != 2.5 {
		t.Fatalf("SetScaleFactor() value=%v error=%v", hub.ScaleFactor(), err)
	}
	if err := hub.SetOffset(7); err != nil || hub.Offset() != 7 {
		t.Fatalf("SetOffset() value=%v error=%v", hub.Offset(), err)
	}
	if err := hub.SetScaleFactor(math.Inf(1)); !errors.Is(err, ErrNonFinite) {
		t.Fatalf("SetScaleFactor(+Inf) error=%v, want %v", err, ErrNonFinite)
	}
	if err := hub.SetThreshold(math.NaN()); !errors.Is(err, ErrNonFinite) {
		t.Fatalf("SetThreshold(NaN) error=%v, want %v", err, ErrNonFinite)
	}
}

func TestIngestionQueriesStatisticsAndTransforms(t *testing.T) {
	hub := newTestHub(t, "analytics", 4, OverflowPolicyReject, func(uint64, float64) int32 { return 0 })
	defer hub.Close()

	if err := hub.PushWithSeverity(10, -2, SeverityWarning); err != nil {
		t.Fatal(err)
	}
	if err := hub.PushBatch([]float64{4, 8}); err != nil {
		t.Fatal(err)
	}
	if hub.Len() != 3 || hub.Accepted() != 3 || hub.Rejected() != 0 || hub.Dropped() != 0 || hub.Processed() != 0 || hub.Filtered() != 0 {
		t.Fatalf("unexpected counters: len=%d accepted=%d rejected=%d dropped=%d processed=%d filtered=%d", hub.Len(), hub.Accepted(), hub.Rejected(), hub.Dropped(), hub.Processed(), hub.Filtered())
	}
	assertUint64Query(t, "FirstID", hub.FirstID, 10)
	assertUint64Query(t, "LastID", hub.LastID, 2)
	assertFloatQuery(t, "FirstValue", hub.FirstValue, -2)
	assertFloatQuery(t, "LastValue", hub.LastValue, 8)
	if got, err := hub.LastSeverity(); err != nil || got != SeverityInfo {
		t.Fatalf("LastSeverity()=(%v,%v), want (%v,nil)", got, err, SeverityInfo)
	}
	assertFloatQuery(t, "Minimum", hub.Minimum, -2)
	assertFloatQuery(t, "Maximum", hub.Maximum, 8)
	assertFloatQuery(t, "Average", hub.Average, 10.0/3.0)
	if hub.Sum() != 10 {
		t.Fatalf("Sum()=%v, want 10", hub.Sum())
	}
	if got, err := hub.CountAbove(0); err != nil || got != 2 {
		t.Fatalf("CountAbove(0)=(%d,%v), want (2,nil)", got, err)
	}
	if got, err := hub.CountBelow(0); err != nil || got != 1 {
		t.Fatalf("CountBelow(0)=(%d,%v), want (1,nil)", got, err)
	}
	if got, err := hub.ContainsAbove(7); err != nil || !got {
		t.Fatalf("ContainsAbove(7)=(%v,%v), want (true,nil)", got, err)
	}
	if got, err := hub.ContainsBelow(-1); err != nil || !got {
		t.Fatalf("ContainsBelow(-1)=(%v,%v), want (true,nil)", got, err)
	}

	hub.AbsoluteValues()
	if err := hub.ScaleValues(2); err != nil {
		t.Fatal(err)
	}
	if err := hub.OffsetValues(1); err != nil {
		t.Fatal(err)
	}
	if err := hub.ClampValues(0, 10); err != nil {
		t.Fatal(err)
	}
	hub.NegateValues()
	assertFloatQuery(t, "Minimum after transforms", hub.Minimum, -10)
	assertFloatQuery(t, "Maximum after transforms", hub.Maximum, -5)
	if err := hub.ClampValues(2, 1); !errors.Is(err, ErrInvalidRange) {
		t.Fatalf("ClampValues(2,1) error=%v, want %v", err, ErrInvalidRange)
	}
	if got := hub.Clear(); got != 3 || !hub.IsEmpty() {
		t.Fatalf("Clear()=%d empty=%v, want 3,true", got, hub.IsEmpty())
	}
	if _, err := hub.Minimum(); !errors.Is(err, ErrEmpty) {
		t.Fatalf("Minimum() on empty hub error=%v, want %v", err, ErrEmpty)
	}
	hub.ResetStatistics()
	if hub.Accepted() != 0 || hub.Rejected() != 0 || hub.Dropped() != 0 {
		t.Fatal("ResetStatistics() did not clear ingestion counters")
	}
}

func TestOverflowDisableAndBatchAtomicity(t *testing.T) {
	hub := newTestHub(t, "backpressure", 2, OverflowPolicyReject, func(uint64, float64) int32 { return 0 })
	defer hub.Close()

	if err := hub.Push(1, 1); err != nil {
		t.Fatal(err)
	}
	if err := hub.PushBatch([]float64{2, 3}); !errors.Is(err, ErrFull) {
		t.Fatalf("oversized PushBatch() error=%v, want %v", err, ErrFull)
	}
	if hub.Len() != 1 || hub.Rejected() != 2 {
		t.Fatalf("rejected batch mutated state: len=%d rejected=%d", hub.Len(), hub.Rejected())
	}
	hub.SetEnabled(false)
	if err := hub.Push(4, 4); !errors.Is(err, ErrDisabled) {
		t.Fatalf("disabled Push() error=%v, want %v", err, ErrDisabled)
	}
	hub.SetEnabled(true)
	hub.SetOverflowPolicy(OverflowPolicyDropOldest)
	if err := hub.Push(2, 2); err != nil {
		t.Fatal(err)
	}
	if err := hub.Push(3, 3); err != nil {
		t.Fatal(err)
	}
	if !hub.IsFull() || hub.Dropped() != 1 {
		t.Fatalf("drop-oldest state: full=%v dropped=%d", hub.IsFull(), hub.Dropped())
	}
	assertUint64Query(t, "FirstID after drop", hub.FirstID, 2)
	if err := hub.Push(4, math.NaN()); !errors.Is(err, ErrNonFinite) {
		t.Fatalf("Push(NaN) error=%v, want %v", err, ErrNonFinite)
	}
}

func TestScaledFilteringProcessingAndObserverPanic(t *testing.T) {
	type observation struct {
		id    uint64
		value float64
	}
	var observed []observation
	hub := newTestHub(t, "processor", 4, OverflowPolicyReject, func(id uint64, value float64) int32 {
		observed = append(observed, observation{id: id, value: value})
		return 0
	})
	defer hub.Close()
	hub.SetMode(ModeScaled)
	if err := hub.SetScaleFactor(2); err != nil {
		t.Fatal(err)
	}
	if err := hub.SetOffset(1); err != nil {
		t.Fatal(err)
	}
	if err := hub.SetThreshold(0); err != nil {
		t.Fatal(err)
	}
	for id, value := range []float64{-2, 3, 4} {
		if err := hub.Push(uint64(id+1), value); err != nil {
			t.Fatal(err)
		}
	}
	if got, err := hub.Process(2); err != nil || got != 2 {
		t.Fatalf("Process(2)=(%d,%v), want (2,nil)", got, err)
	}
	if got, err := hub.ProcessAll(); err != nil || got != 1 {
		t.Fatalf("ProcessAll()=(%d,%v), want (1,nil)", got, err)
	}
	if fmt.Sprint(observed) != "[{2 7} {3 9}]" || hub.Processed() != 2 || hub.Filtered() != 1 {
		t.Fatalf("observed=%v processed=%d filtered=%d", observed, hub.Processed(), hub.Filtered())
	}
	if _, err := hub.Process(0); !errors.Is(err, ErrInvalidLimit) {
		t.Fatalf("Process(0) error=%v, want %v", err, ErrInvalidLimit)
	}
	if _, err := hub.ProcessAll(); !errors.Is(err, ErrEmpty) {
		t.Fatalf("empty ProcessAll() error=%v, want %v", err, ErrEmpty)
	}

	panicking := newTestHub(t, "panic", 1, OverflowPolicyReject, func(uint64, float64) int32 {
		panic("deliberate observer panic")
	})
	if err := panicking.Push(1, 42); err != nil {
		t.Fatal(err)
	}
	if _, err := panicking.ProcessAll(); !errors.Is(err, ErrObserverPanicked) {
		t.Fatalf("panicking observer error=%v, want %v", err, ErrObserverPanicked)
	}
	if panicking.Len() != 1 {
		t.Fatalf("observer panic consumed sample: len=%d", panicking.Len())
	}
	panicking.Close()
}

func TestFailedConstructionAndIndependentConcurrentLifecycles(t *testing.T) {
	observer := func(uint64, float64) int32 { return 0 }
	if _, err := NewTelemetryHub("", 1, ModeRaw, OverflowPolicyReject, observer); !errors.Is(err, ErrInvalidName) {
		t.Fatalf("empty-name constructor error=%v, want %v", err, ErrInvalidName)
	}
	if _, err := NewTelemetryHub("invalid", 0, ModeRaw, OverflowPolicyReject, observer); !errors.Is(err, ErrInvalidCapacity) {
		t.Fatalf("zero-capacity constructor error=%v, want %v", err, ErrInvalidCapacity)
	}
	assertNoLiveResources(t)

	const workers = 6
	const iterations = 12
	var wait sync.WaitGroup
	errs := make(chan error, workers)
	for worker := range workers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			for iteration := range iterations {
				count := 0
				hub, err := NewTelemetryHub(fmt.Sprintf("worker-%d-%d", worker, iteration), 3, ModeAbsolute, OverflowPolicyReject, func(uint64, float64) int32 {
					count++
					return 0
				})
				if err == nil {
					err = hub.PushBatch([]float64{-1, -2, -3})
				}
				var processed uint
				if err == nil {
					processed, err = hub.ProcessAll()
				}
				if hub != nil {
					hub.Close()
					hub.Close()
				}
				if err != nil || processed != 3 || count != 3 {
					errs <- fmt.Errorf("worker=%d iteration=%d processed=%d observed=%d err=%v", worker, iteration, processed, count, err)
					return
				}
			}
		}()
	}
	wait.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	assertNoLiveResources(t)
}

func newTestHub(t *testing.T, name string, capacity uint, policy OverflowPolicy, observer TelemetryHubObserver) *TelemetryHub {
	t.Helper()
	hub, err := NewTelemetryHub(name, capacity, ModeRaw, policy, observer)
	if err != nil {
		t.Fatal(err)
	}
	return hub
}

func assertUint64Query(t *testing.T, name string, query func() (uint64, error), want uint64) {
	t.Helper()
	got, err := query()
	if err != nil || got != want {
		t.Fatalf("%s()=(%d,%v), want (%d,nil)", name, got, err, want)
	}
}

func assertFloatQuery(t *testing.T, name string, query func() (float64, error), want float64) {
	t.Helper()
	got, err := query()
	if err != nil || math.Abs(got-want) > 1e-12 {
		t.Fatalf("%s()=(%v,%v), want (%v,nil)", name, got, err, want)
	}
}

func assertNoLiveResources(t *testing.T) {
	t.Helper()
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("active callback handles=%d, want 0", got)
	}
	if got := LiveHubs(); got != 0 {
		t.Fatalf("LiveHubs()=%d, want 0", got)
	}
}
