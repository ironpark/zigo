package pipeline

import (
	"errors"
	"fmt"
	"sync"
	"testing"
)

func TestPipelineEndToEnd(t *testing.T) {
	pipeline, err := NewPipeline("복합 파이프라인", ModeWeighted, func(value int32) int32 {
		return value + 10
	})
	if err != nil {
		t.Fatal(err)
	}
	defer pipeline.Close()

	if got := pipeline.Name(); got != "복합 파이프라인" {
		t.Fatalf("Name() = %q", got)
	}
	if got := pipeline.Mode(); got != ModeWeighted {
		t.Fatalf("Mode() = %v, want %v", got, ModeWeighted)
	}
	got, err := pipeline.Process([]int32{1, 2, 3})
	if err != nil {
		t.Fatal(err)
	}
	if got != 74 {
		t.Fatalf("Process() = %d, want 74", got)
	}
	if got := pipeline.Processed(); got != 3 {
		t.Fatalf("Processed() = %d, want 3", got)
	}
	if got := pipeline.Total(); got != 74 {
		t.Fatalf("Total() = %d, want 74", got)
	}

	if previous := pipeline.SetEnabled(false); !previous {
		t.Fatal("SetEnabled(false) previous = false, want true")
	}
	if _, err := pipeline.Process([]int32{1}); !errors.Is(err, ErrDisabled) {
		t.Fatalf("disabled Process() error = %v, want %v", err, ErrDisabled)
	}
	if previous := pipeline.SetEnabled(true); previous {
		t.Fatal("SetEnabled(true) previous = true, want false")
	}
	if _, err := pipeline.Process(nil); !errors.Is(err, ErrEmptyInput) {
		t.Fatalf("empty Process() error = %v, want %v", err, ErrEmptyInput)
	}
}

func TestConstructorFailureReleasesCallback(t *testing.T) {
	if _, err := NewPipeline("", ModeSum, func(value int32) int32 { return value }); !errors.Is(err, ErrInvalidName) {
		t.Fatalf("NewPipeline() error = %v, want %v", err, ErrInvalidName)
	}
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("active callback handles = %d, want 0", got)
	}
	if got := LiveBytes(); got != 0 {
		t.Fatalf("LiveBytes() = %d, want 0", got)
	}
}

func TestCallbackPanicBecomesTypedError(t *testing.T) {
	pipeline, err := NewPipeline("panic boundary", ModeSum, func(int32) int32 {
		panic("deliberate Go callback panic")
	})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := pipeline.Process([]int32{1}); !errors.Is(err, ErrCallbackPanicked) {
		t.Fatalf("Process() error = %v, want %v", err, ErrCallbackPanicked)
	}
	pipeline.Close()
	pipeline.Close()
	assertNoLiveResources(t)
}

func TestGenericBatchSpecializations(t *testing.T) {
	ints, err := NewIntBatch()
	if err != nil {
		t.Fatal(err)
	}
	defer ints.Close()
	for _, value := range []int32{2, 3, 5} {
		if err := ints.Push(value); err != nil {
			t.Fatal(err)
		}
	}
	if got := ints.Len(); got != 3 {
		t.Fatalf("IntBatch.Len() = %d, want 3", got)
	}

	floats, err := NewFloatBatch()
	if err != nil {
		t.Fatal(err)
	}
	defer floats.Close()
	if err := floats.Push(1.25); err != nil {
		t.Fatal(err)
	}
	if got := floats.Len(); got != 1 {
		t.Fatalf("FloatBatch.Len() = %d, want 1", got)
	}
}

func TestConcurrentPipelineLifecycle(t *testing.T) {
	const workers = 8
	const iterations = 40

	var wait sync.WaitGroup
	errs := make(chan error, workers)
	for worker := range workers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			for iteration := range iterations {
				pipeline, err := NewPipeline(fmt.Sprintf("worker-%d-%d", worker, iteration), ModeSum, func(value int32) int32 {
					return value * 2
				})
				if err != nil {
					errs <- err
					return
				}
				got, err := pipeline.Process([]int32{1, 2, 3})
				pipeline.Close()
				pipeline.Close()
				if err != nil {
					errs <- err
					return
				}
				if got != 12 {
					errs <- fmt.Errorf("worker %d iteration %d: Process() = %d, want 12", worker, iteration, got)
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

func TestSystemLibraryLinkIsPropagated(t *testing.T) {
	if got := CompressionBound(1024); got <= 1024 {
		t.Fatalf("CompressionBound(1024) = %d, want > 1024", got)
	}
}

func assertNoLiveResources(t *testing.T) {
	t.Helper()
	if got := activeCallbackHandleCount(); got != 0 {
		t.Fatalf("active callback handles = %d, want 0", got)
	}
	if got := LiveBytes(); got != 0 {
		t.Fatalf("LiveBytes() = %d, want 0", got)
	}
}

func BenchmarkPipelineProcess(b *testing.B) {
	pipeline, err := NewPipeline("benchmark", ModeWeighted, func(value int32) int32 {
		return value + 1
	})
	if err != nil {
		b.Fatal(err)
	}
	defer pipeline.Close()

	values := make([]int32, 64)
	for index := range values {
		values[index] = int32(index)
	}
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		if _, err := pipeline.Process(values); err != nil {
			b.Fatal(err)
		}
	}
}
