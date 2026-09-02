package telemetry_hub

import (
	"errors"
	"fmt"
	"io"
	"math"
	"sync"
	"testing"
)

var _ TelemetryHubObserver = func(uint64, float64) int32 { return 0 }

// A generated handle closes like any other Go resource.
var _ io.Closer = (*TelemetryHub)(nil)

// must unwraps a generated call whose only failure mode here would be a nil or
// closed handle.
func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

func TestConfigurationAndEnumSurface(t *testing.T) {
	if ModeScaled.String() != "scaled" || OverflowPolicyDropOldest.String() != "drop_oldest" || SeverityCritical.String() != "critical" {
		t.Fatal("generated enum names do not match Zig tags")
	}
	hub, err := NewTelemetryHub("서울 관측소", 4, ModeRaw, OverflowPolicyReject, func(uint64, float64) int32 { return 0 })
	if err != nil {
		t.Fatal(err)
	}
	defer hub.Close()

	if must(hub.Name()) != "서울 관측소" || must(hub.Capacity()) != 4 || !must(hub.Enabled()) || !must(hub.IsEmpty()) || must(hub.IsFull()) {
		t.Fatalf("unexpected initial state: name=%q capacity=%d enabled=%v empty=%v full=%v", must(hub.Name()), must(hub.Capacity()), must(hub.Enabled()), must(hub.IsEmpty()), must(hub.IsFull()))
	}
	if err := hub.Rename("edge/α-02"); err != nil || must(hub.Name()) != "edge/α-02" {
		t.Fatalf("Rename() state = %q, error = %v", must(hub.Name()), err)
	}
	if previous := must(hub.SetMode(ModeScaled)); previous != ModeRaw || must(hub.Mode()) != ModeScaled {
		t.Fatalf("SetMode() previous=%v current=%v", previous, must(hub.Mode()))
	}
	if previous := must(hub.SetOverflowPolicy(OverflowPolicyDropOldest)); previous != OverflowPolicyReject || must(hub.OverflowPolicy()) != OverflowPolicyDropOldest {
		t.Fatalf("SetOverflowPolicy() previous=%v current=%v", previous, must(hub.OverflowPolicy()))
	}
	if previous := must(hub.SetEnabled(false)); !previous || must(hub.Enabled()) {
		t.Fatalf("SetEnabled(false) previous=%v current=%v", previous, must(hub.Enabled()))
	}
	must(hub.SetEnabled(true))
	if err := hub.SetThreshold(-12.5); err != nil || must(hub.Threshold()) != -12.5 {
		t.Fatalf("SetThreshold() value=%v error=%v", must(hub.Threshold()), err)
	}
	if err := hub.SetScaleFactor(2.5); err != nil || must(hub.ScaleFactor()) != 2.5 {
		t.Fatalf("SetScaleFactor() value=%v error=%v", must(hub.ScaleFactor()), err)
	}
	if err := hub.SetOffset(7); err != nil || must(hub.Offset()) != 7 {
		t.Fatalf("SetOffset() value=%v error=%v", must(hub.Offset()), err)
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
	if must(hub.Len()) != 3 || must(hub.Accepted()) != 3 || must(hub.Rejected()) != 0 || must(hub.Dropped()) != 0 || must(hub.Processed()) != 0 || must(hub.Filtered()) != 0 {
		t.Fatalf("unexpected counters: len=%d accepted=%d rejected=%d dropped=%d processed=%d filtered=%d", must(hub.Len()), must(hub.Accepted()), must(hub.Rejected()), must(hub.Dropped()), must(hub.Processed()), must(hub.Filtered()))
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
	if must(hub.Sum()) != 10 {
		t.Fatalf("Sum()=%v, want 10", must(hub.Sum()))
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
	if got := must(hub.Clear()); got != 3 || !must(hub.IsEmpty()) {
		t.Fatalf("Clear()=%d empty=%v, want 3,true", got, must(hub.IsEmpty()))
	}
	if _, err := hub.Minimum(); !errors.Is(err, ErrEmpty) {
		t.Fatalf("Minimum() on empty hub error=%v, want %v", err, ErrEmpty)
	}
	hub.ResetStatistics()
	if must(hub.Accepted()) != 0 || must(hub.Rejected()) != 0 || must(hub.Dropped()) != 0 {
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
	if must(hub.Len()) != 1 || must(hub.Rejected()) != 2 {
		t.Fatalf("rejected batch mutated state: len=%d rejected=%d", must(hub.Len()), must(hub.Rejected()))
	}
	must(hub.SetEnabled(false))
	if err := hub.Push(4, 4); !errors.Is(err, ErrDisabled) {
		t.Fatalf("disabled Push() error=%v, want %v", err, ErrDisabled)
	}
	must(hub.SetEnabled(true))
	must(hub.SetOverflowPolicy(OverflowPolicyDropOldest))
	if err := hub.Push(2, 2); err != nil {
		t.Fatal(err)
	}
	if err := hub.Push(3, 3); err != nil {
		t.Fatal(err)
	}
	if !must(hub.IsFull()) || must(hub.Dropped()) != 1 {
		t.Fatalf("drop-oldest state: full=%v dropped=%d", must(hub.IsFull()), must(hub.Dropped()))
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
	must(hub.SetMode(ModeScaled))
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
	if fmt.Sprint(observed) != "[{2 7} {3 9}]" || must(hub.Processed()) != 2 || must(hub.Filtered()) != 1 {
		t.Fatalf("observed=%v processed=%d filtered=%d", observed, must(hub.Processed()), must(hub.Filtered()))
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
	expectCallbackPanic(t, "TelemetryHub.ProcessAll", "deliberate observer panic", func() { _, _ = panicking.ProcessAll() })
	if must(panicking.Len()) != 1 {
		t.Fatalf("observer panic consumed sample: len=%d", must(panicking.Len()))
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

// expectCallbackPanic runs call and requires it to panic with the
// *CallbackPanicError the binding rethrows for a Go callback panic. It
// returns the error for further inspection.
func expectCallbackPanic(t *testing.T, operation string, value any, call func()) *CallbackPanicError {
	t.Helper()
	var recovered any
	func() {
		defer func() { recovered = recover() }()
		call()
	}()
	err, ok := recovered.(error)
	if !ok {
		t.Fatalf("recovered %v (%T), want *CallbackPanicError", recovered, recovered)
	}
	var panicErr *CallbackPanicError
	if !errors.As(err, &panicErr) {
		t.Fatalf("recovered %v, want *CallbackPanicError", err)
	}
	if !errors.Is(err, ErrCallbackPanic) {
		t.Fatalf("errors.Is(%v, ErrCallbackPanic) = false", err)
	}
	if panicErr.Operation != operation {
		t.Fatalf("Operation = %q, want %q", panicErr.Operation, operation)
	}
	if panicErr.Value != value {
		t.Fatalf("Value = %v, want %v", panicErr.Value, value)
	}
	if len(panicErr.Stack) == 0 {
		t.Fatal("Stack is empty")
	}
	return panicErr
}
