package telemetry_hub

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
)

func init() {
	// An explicit path keeps the test independent of the loader search path;
	// ZIGO_LIBRARY_PATH still wins so the artifact can be installed elsewhere.
	_, file, _, _ := runtime.Caller(0)
	path := os.Getenv("ZIGO_LIBRARY_PATH")
	if path == "" {
		path = filepath.Join(filepath.Dir(file), "..", "..", "zig-out", "lib", DefaultLibraryName)
	}
	if err := LoadLibrary(path); err != nil {
		panic(err)
	}
}

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
	if _, err := panicking.ProcessAll(); !errors.Is(err, ErrObserverPanicked) {
		t.Fatalf("panic error = %v", err)
	}
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
