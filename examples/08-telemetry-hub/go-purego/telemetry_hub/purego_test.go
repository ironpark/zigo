package telemetry_hub

import (
	"errors"
	"fmt"
	"math"
	"sync"
	"testing"
)

// This binding set uses an automatic loading policy with an internal loader, so
// the tests call no loader function: the first binding call finds the library
// through the configured search paths.

func TestPuregoTelemetryPipelineAndPanic(t *testing.T) {
	var values []float64
	hub, err := NewTelemetryHub("broad", 4, ModeScaled, OverflowPolicyReject, func(_ uint64, value float64) int32 {
		values = append(values, value)
		return 0
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := hub.SetScaleFactor(2); err != nil {
		t.Fatal(err)
	}
	if err := hub.SetOffset(1); err != nil {
		t.Fatal(err)
	}
	if err := hub.PushBatch([]float64{1, 2, 3}); err != nil {
		t.Fatal(err)
	}
	if got, err := hub.ProcessAll(); err != nil || got != 3 {
		t.Fatalf("ProcessAll = %d, %v", got, err)
	}
	if fmt.Sprint(values) != "[3 5 7]" {
		t.Fatalf("values = %v", values)
	}
	hub.Close()

	panicking, err := NewTelemetryHub("panic", 1, ModeRaw, OverflowPolicyReject, func(uint64, float64) int32 { panic("observer") })
	if err != nil {
		t.Fatal(err)
	}
	if err := panicking.Push(1, 2); err != nil {
		t.Fatal(err)
	}
	expectCallbackPanic(t, "TelemetryHub.ProcessAll", "observer", func() { _, _ = panicking.ProcessAll() })
	panicking.Close()
	if activeCallbackHandleCount() != 0 {
		t.Fatalf("callback leak = %d", activeCallbackHandleCount())
	}
}

func TestPuregoConcurrentIndependentLifecycles(t *testing.T) {
	const workers = 8
	const iterations = 20
	var wait sync.WaitGroup
	errs := make(chan error, workers)
	for worker := range workers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			for iteration := range iterations {
				hub, err := NewTelemetryHub(fmt.Sprintf("hub-%d-%d", worker, iteration), 2, ModeRaw, OverflowPolicyReject, func(uint64, float64) int32 { return 0 })
				if err == nil {
					err = hub.PushBatch([]float64{1, 2})
				}
				if err == nil {
					_, err = hub.ProcessAll()
				}
				if hub != nil {
					hub.Close()
					hub.Close()
				}
				if err != nil {
					errs <- err
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
	if activeCallbackHandleCount() != 0 || LiveHubs() != 0 {
		t.Fatalf("lifecycle leak: callbacks=%d hubs=%d", activeCallbackHandleCount(), LiveHubs())
	}
	if callbackDispatcherCount() != 1 {
		t.Fatalf("dispatchers = %d", callbackDispatcherCount())
	}
}

// Float callback parameters cross the purego ABI as IEEE-754 bit patterns, so
// what matters is that the observer sees the exact bits the native side
// produced -- not a value that merely prints the same. Negative zero and an
// infinity are the payloads a lossy conversion would quietly normalise away.
func TestPuregoFloatCallbackParameterIsBitExact(t *testing.T) {
	observe := func(t *testing.T, mode Mode, configure func(*TelemetryHub) error, push float64) uint64 {
		t.Helper()
		var seen []float64
		hub, err := NewTelemetryHub("bits", 1, mode, OverflowPolicyReject, func(_ uint64, value float64) int32 {
			seen = append(seen, value)
			return 0
		})
		if err != nil {
			t.Fatal(err)
		}
		defer hub.Close()
		if configure != nil {
			if err := configure(hub); err != nil {
				t.Fatal(err)
			}
		}
		if err := hub.Push(1, push); err != nil {
			t.Fatal(err)
		}
		if _, err := hub.ProcessAll(); err != nil {
			t.Fatal(err)
		}
		if len(seen) != 1 {
			t.Fatalf("observed %d values, want 1", len(seen))
		}
		return math.Float64bits(seen[0])
	}

	ordinary := 3.141592653589793
	if got := observe(t, ModeRaw, nil, ordinary); got != math.Float64bits(ordinary) {
		t.Errorf("ordinary value = %#016x, want %#016x", got, math.Float64bits(ordinary))
	}
	// The sign bit is the whole point: -0.0 and 0.0 compare equal, so the test
	// has to look at the bits.
	negativeZero := math.Copysign(0, -1)
	if got := observe(t, ModeRaw, nil, negativeZero); got != math.Float64bits(negativeZero) {
		t.Errorf("negative zero = %#016x, want %#016x", got, math.Float64bits(negativeZero))
	}
	// Push refuses a non-finite sample, so the infinity is produced natively:
	// scaled mode overflows the product into +Inf on the Zig side.
	toInfinity := func(hub *TelemetryHub) error { return hub.SetScaleFactor(1e308) }
	if got := observe(t, ModeScaled, toInfinity, 1e308); got != math.Float64bits(math.Inf(1)) {
		t.Errorf("positive infinity = %#016x, want %#016x", got, math.Float64bits(math.Inf(1)))
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
