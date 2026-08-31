package tagged_union

import (
	"errors"
	"reflect"
	"runtime"
	"testing"
	"time"

	"example.com/zigo/tagged-union/internal/raw"
)

// must unwraps a generated call whose only failure mode in these tests would be
// a nil or closed handle, which the tests establish is not the case.
func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

// must2 is must for the projection accessors, which also report whether the
// variant is active.
func must2[T any](value T, matched bool, err error) (T, bool) {
	if err != nil {
		panic(err)
	}
	return value, matched
}

func TestGeneratedTagAndCheckedPayloadAccessors(t *testing.T) {
	value, err := NewValue(42)
	if err != nil {
		t.Fatal(err)
	}
	defer value.Close()

	if got, err := value.Tag(); err != nil || got != ValueTagInteger {
		t.Fatalf("Tag() = (%v, %v), want (%v, nil)", got, err, ValueTagInteger)
	}
	if got := value.MustTag(); got != ValueTagInteger {
		t.Fatalf("MustTag() = %v, want %v", got, ValueTagInteger)
	}
	if got, ok, err := value.AsInteger(); err != nil || !ok || got != 42 {
		t.Fatalf("AsInteger() = (%d, %v, %v), want (42, true, nil)", got, ok, err)
	}
	if got, ok := value.MustAsInteger(); !ok || got != 42 {
		t.Fatalf("MustAsInteger() = (%d, %v), want (42, true)", got, ok)
	}
	if got, ok, err := value.AsFlag(); err != nil || ok || got {
		t.Fatalf("AsFlag() on integer = (%v, %v, %v), want (false, false, nil)", got, ok, err)
	}

	if err := value.SetFlag(true); err != nil {
		t.Fatal(err)
	}
	if got, ok := must2(value.AsFlag()); !ok || !got {
		t.Fatalf("AsFlag() = (%v, %v), want (true, true)", got, ok)
	}
	if err := value.SetMode(ModePaused); err != nil {
		t.Fatal(err)
	}
	if got, ok := must2(value.AsMode()); !ok || got != ModePaused {
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

	if err := value.UsePresetSamples(); err != nil {
		t.Fatal(err)
	}
	first, ok := must2(value.AsSamples())
	if !ok || !reflect.DeepEqual(first, []int16{3, 5, 8, 13}) {
		t.Fatalf("AsSamples() = (%v, %v)", first, ok)
	}
	first[0] = 99
	second, ok := must2(value.AsSamples())
	if !ok || second[0] != 3 {
		t.Fatalf("AsSamples() did not return an independent copy: (%v, %v)", second, ok)
	}

	if err := value.UseEmptySamples(); err != nil {
		t.Fatal(err)
	}
	empty, ok := must2(value.AsSamples())
	if !ok || len(empty) != 0 {
		t.Fatalf("AsSamples() for empty payload = (%v, %v)", empty, ok)
	}

	if err := value.UseMutableSamples(); err != nil {
		t.Fatal(err)
	}
	mutable, ok := must2(value.AsMutableSamples())
	if !ok || !reflect.DeepEqual(mutable, []int16{21, 34, 55}) {
		t.Fatalf("AsMutableSamples() = (%v, %v)", mutable, ok)
	}
	mutable[0] = 99
	again, ok := must2(value.AsMutableSamples())
	if !ok || again[0] != 21 {
		t.Fatalf("AsMutableSamples() exposed native memory: (%v, %v)", again, ok)
	}

	if err := value.SetChild(child); err != nil {
		t.Fatal(err)
	}
	borrowed := must(value.Borrow())
	if got := must(borrowed.Tag()); got != ValueTagChild {
		t.Fatalf("borrowed Tag() = %v, want %v", got, ValueTagChild)
	}
	childRef, ok := must2(borrowed.AsChild())
	if !ok || childRef == nil {
		t.Fatalf("borrowed AsChild() = (%v, %v)", childRef, ok)
	}
}

func TestProjectionLifecycleFailuresStayInGo(t *testing.T) {
	if _, status := raw.ValueProjectTag(nil); status != zigoProjectionInvalidHandle {
		t.Fatalf("raw nil projection status = %d, want %d", status, zigoProjectionInvalidHandle)
	}

	// The plain names report the failure; only the Must variants panic.
	assertInvalidHandleError(t, "Value.Tag receiver", func() error {
		_, err := (*Value)(nil).Tag()
		return err
	})
	assertInvalidHandleError(t, "Value.AsInteger receiver", func() error {
		_, _, err := (*Value)(nil).AsInteger()
		return err
	})
	assertHandlePanic(t, "Value.Tag receiver", func() { (*Value)(nil).MustTag() })
	assertHandlePanic(t, "Value.AsInteger receiver", func() { (*Value)(nil).MustAsInteger() })

	value, err := NewValue(7)
	if err != nil {
		t.Fatal(err)
	}
	borrowed := must(value.Borrow())
	value.Close()

	assertHandlePanic(t, "Value.Tag receiver", func() { value.MustTag() })
	assertHandlePanic(t, "Value.AsInteger receiver", func() { value.MustAsInteger() })
	assertHandlePanic(t, "Value.Tag receiver", func() { borrowed.MustTag() })
	assertInvalidHandleError(t, "Value.SetFlag receiver", func() error { return value.SetFlag(true) })
	assertInvalidHandleError(t, "Value.Borrow receiver", func() error {
		_, err := value.Borrow()
		return err
	})
	assertInvalidHandleError(t, "Value.Tag receiver", func() error {
		_, err := borrowed.Tag()
		return err
	})
}

func TestOpaqueArgumentsAndNativeErrorsAreTyped(t *testing.T) {
	child, err := NewChild(11)
	if err != nil {
		t.Fatal(err)
	}
	child.Close()
	assertInvalidHandleError(t, "Child.Get receiver", func() error {
		_, err := child.Get()
		return err
	})

	value, err := NewValue(1)
	if err != nil {
		t.Fatal(err)
	}
	defer value.Close()
	assertInvalidHandleError(t, "Value.SetChild parameter child", func() error { return value.SetChild(child) })

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
		if must(value.Tag()) != ValueTagInteger {
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
