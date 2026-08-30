package tagged_union

import (
	"errors"
	"reflect"
	"runtime"
	"testing"
	"time"

	"example.com/zigo/tagged-union/internal/raw"
)

func TestGeneratedTagAndCheckedPayloadAccessors(t *testing.T) {
	value, err := NewValue(42)
	if err != nil {
		t.Fatal(err)
	}
	defer value.Close()

	if got := value.Tag(); got != ValueTagInteger {
		t.Fatalf("Tag() = %v, want %v", got, ValueTagInteger)
	}
	if got, err := value.TryTag(); err != nil || got != ValueTagInteger {
		t.Fatalf("TryTag() = (%v, %v), want (%v, nil)", got, err, ValueTagInteger)
	}
	if got, ok := value.AsInteger(); !ok || got != 42 {
		t.Fatalf("AsInteger() = (%d, %v), want (42, true)", got, ok)
	}
	if got, ok, err := value.TryAsInteger(); err != nil || !ok || got != 42 {
		t.Fatalf("TryAsInteger() = (%d, %v, %v), want (42, true, nil)", got, ok, err)
	}
	if got, ok := value.AsFlag(); ok || got {
		t.Fatalf("AsFlag() on integer = (%v, %v), want (false, false)", got, ok)
	}
	if got, ok, err := value.TryAsFlag(); err != nil || ok || got {
		t.Fatalf("TryAsFlag() on integer = (%v, %v, %v), want (false, false, nil)", got, ok, err)
	}

	value.SetFlag(true)
	if got, ok := value.AsFlag(); !ok || !got {
		t.Fatalf("AsFlag() = (%v, %v), want (true, true)", got, ok)
	}
	value.SetMode(ModePaused)
	if got, ok := value.AsMode(); !ok || got != ModePaused {
		t.Fatalf("AsMode() = (%v, %v), want (%v, true)", got, ok, ModePaused)
	}
}

func TestSliceIsCopiedAndBorrowedHandleHasAccessors(t *testing.T) {
	child, err := NewChild(17)
	if err != nil {
		t.Fatal(err)
	}
	defer child.Close()
	value, err := NewValue(1)
	if err != nil {
		t.Fatal(err)
	}
	defer value.Close()

	value.UsePresetSamples()
	first, ok := value.AsSamples()
	if !ok || !reflect.DeepEqual(first, []int16{3, 5, 8, 13}) {
		t.Fatalf("AsSamples() = (%v, %v)", first, ok)
	}
	first[0] = 99
	second, ok := value.AsSamples()
	if !ok || second[0] != 3 {
		t.Fatalf("AsSamples() did not return an independent copy: (%v, %v)", second, ok)
	}

	value.UseEmptySamples()
	empty, ok := value.AsSamples()
	if !ok || len(empty) != 0 {
		t.Fatalf("AsSamples() for empty payload = (%v, %v)", empty, ok)
	}

	value.UseMutableSamples()
	mutable, ok := value.AsMutableSamples()
	if !ok || !reflect.DeepEqual(mutable, []int16{21, 34, 55}) {
		t.Fatalf("AsMutableSamples() = (%v, %v)", mutable, ok)
	}
	mutable[0] = 99
	again, ok := value.AsMutableSamples()
	if !ok || again[0] != 21 {
		t.Fatalf("AsMutableSamples() exposed native memory: (%v, %v)", again, ok)
	}

	value.SetChild(child)
	borrowed := value.Borrow()
	if borrowed.Tag() != ValueTagChild {
		t.Fatalf("borrowed Tag() = %v, want %v", borrowed.Tag(), ValueTagChild)
	}
	childRef, ok := borrowed.AsChild()
	if !ok || childRef == nil {
		t.Fatalf("borrowed AsChild() = (%v, %v)", childRef, ok)
	}
}

func TestProjectionLifecycleFailuresStayInGo(t *testing.T) {
	if _, status := raw.ValueProjectTag(nil); status != zigoProjectionInvalidHandle {
		t.Fatalf("raw nil projection status = %d, want %d", status, zigoProjectionInvalidHandle)
	}

	assertHandlePanic(t, "Value.Tag receiver", func() { (*Value)(nil).Tag() })
	assertHandlePanic(t, "Value.AsInteger receiver", func() { (*Value)(nil).AsInteger() })
	assertInvalidHandleError(t, "Value.Tag receiver", func() error {
		_, err := (*Value)(nil).TryTag()
		return err
	})
	assertInvalidHandleError(t, "Value.AsInteger receiver", func() error {
		_, _, err := (*Value)(nil).TryAsInteger()
		return err
	})

	value, err := NewValue(7)
	if err != nil {
		t.Fatal(err)
	}
	borrowed := value.Borrow()
	value.Close()

	assertHandlePanic(t, "Value.Tag receiver", func() { value.Tag() })
	assertHandlePanic(t, "Value.AsInteger receiver", func() { value.AsInteger() })
	assertHandlePanic(t, "Value.Tag receiver", func() { borrowed.Tag() })
	assertHandlePanic(t, "Value.SetFlag receiver", func() { value.SetFlag(true) })
	assertHandlePanic(t, "Value.Borrow receiver", func() { value.Borrow() })
	assertInvalidHandleError(t, "Value.Tag receiver", func() error {
		_, err := borrowed.TryTag()
		return err
	})
}

func TestOpaqueArgumentsAndNativeProjectionErrorsAreTyped(t *testing.T) {
	child, err := NewChild(11)
	if err != nil {
		t.Fatal(err)
	}
	child.Close()
	assertHandlePanic(t, "Child.Get receiver", func() { child.Get() })

	value, err := NewValue(1)
	if err != nil {
		t.Fatal(err)
	}
	defer value.Close()
	assertHandlePanic(t, "Value.SetChild parameter child", func() { value.SetChild(child) })

	projectionErr := zigoProjectionError("Value.Tag", zigoProjectionPanic)
	if !errors.Is(projectionErr, ErrNativePanic) {
		t.Fatalf("errors.Is(%v, ErrNativePanic) = false", projectionErr)
	}
	var nativeErr *NativePanicError
	if !errors.As(projectionErr, &nativeErr) || nativeErr.Operation != "Value.Tag" {
		t.Fatalf("native projection error = %#v", projectionErr)
	}
}

func assertInvalidHandleError(t *testing.T, operation string, call func() error) {
	t.Helper()
	err := call()
	if !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("errors.Is(%v, ErrInvalidHandle) = false", err)
	}
	var handleErr *HandleError
	if !errors.As(err, &handleErr) || handleErr.Operation != operation {
		t.Fatalf("handle error = %#v, want operation %q", err, operation)
	}
}

func assertHandlePanic(t *testing.T, operation string, call func()) {
	t.Helper()
	defer func() {
		value := recover()
		if value == nil {
			t.Fatalf("%s did not panic", operation)
		}
		err, ok := value.(error)
		if !ok || !errors.Is(err, ErrInvalidHandle) {
			t.Fatalf("%s panic = %#v", operation, value)
		}
		var handleErr *HandleError
		if !errors.As(err, &handleErr) || handleErr.Operation != operation {
			t.Fatalf("%s panic error = %#v", operation, err)
		}
	}()
	call()
}

func TestRuntimeCleanupAfterProjectionUse(t *testing.T) {
	if got := LiveValues(); got != 0 {
		t.Fatalf("LiveValues() before cleanup test = %d, want 0", got)
	}
	func() {
		value, err := NewValue(9)
		if err != nil {
			t.Fatal(err)
		}
		if value.Tag() != ValueTagInteger {
			t.Fatal("unexpected tag before cleanup")
		}
		runtime.KeepAlive(value)
	}()

	deadline := time.Now().Add(5 * time.Second)
	for LiveValues() != 0 {
		runtime.GC()
		runtime.Gosched()
		if time.Now().After(deadline) {
			t.Fatalf("runtime cleanup timed out: live values=%d", LiveValues())
		}
		time.Sleep(10 * time.Millisecond)
	}
}
