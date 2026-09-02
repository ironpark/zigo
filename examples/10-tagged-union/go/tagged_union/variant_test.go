package tagged_union

import (
	"errors"
	"reflect"
	"testing"
)

// assertValueVariants drives every Value variant through one type switch. Value
// is a projection-backed union, so the builder reads the tag and then only the
// projection the active variant needs.
func assertValueVariants(t *testing.T) {
	t.Helper()

	child, err := NewChild(17)
	if err != nil {
		t.Fatal(err)
	}
	defer child.Close()
	value, err := NewValue(42)
	if err != nil {
		t.Fatal(err)
	}
	defer value.Close()

	// A type switch replaces the Tag()-then-As* probe entirely.
	switch active := must(value.Variant()).(type) {
	case ValueInteger:
		if active.Value != 42 {
			t.Fatalf("ValueInteger.Value = %d, want 42", active.Value)
		}
	default:
		t.Fatalf("Variant() = %T, want ValueInteger", active)
	}

	if err := value.SetNone(); err != nil {
		t.Fatal(err)
	}
	// A payloadless variant is an empty struct, so its mere type is the answer.
	if got, want := must(value.Variant()), (ValueNone{}); got != ValueVariant(want) {
		t.Fatalf("Variant() = %#v, want %#v", got, want)
	}

	if err := value.SetFlag(true); err != nil {
		t.Fatal(err)
	}
	assertVariant[ValueVariant](t, value, ValueFlag{Value: true})

	if err := value.SetMode(ModePaused); err != nil {
		t.Fatal(err)
	}
	assertVariant[ValueVariant](t, value, ValueMode{Value: ModePaused})

	if err := value.UsePresetSamples(); err != nil {
		t.Fatal(err)
	}
	samples, ok := must(value.Variant()).(ValueSamples)
	if !ok || !reflect.DeepEqual(samples.Value, []int16{3, 5, 8, 13}) {
		t.Fatalf("Variant() = %#v, want ValueSamples{3 5 8 13}", samples)
	}
	// The slice payload is copied per read, exactly as AsSamples copies it.
	samples.Value[0] = 99
	if again := must(value.Variant()).(ValueSamples); again.Value[0] != 3 {
		t.Fatalf("Variant() slice payload is not an independent copy: %v", again.Value)
	}

	if err := value.UseEmptySamples(); err != nil {
		t.Fatal(err)
	}
	if empty := must(value.Variant()).(ValueSamples); len(empty.Value) != 0 {
		t.Fatalf("empty ValueSamples.Value = %v", empty.Value)
	}

	if err := value.UseMutableSamples(); err != nil {
		t.Fatal(err)
	}
	mutable, ok := must(value.Variant()).(ValueMutableSamples)
	if !ok || !reflect.DeepEqual(mutable.Value, []int16{21, 34, 55}) {
		t.Fatalf("Variant() = %#v, want ValueMutableSamples{21 34 55}", mutable)
	}
	mutable.Value[0] = 99
	if again := must(value.Variant()).(ValueMutableSamples); again.Value[0] != 21 {
		t.Fatalf("Variant() exposed native memory: %v", again.Value)
	}

	if err := value.SetChild(child); err != nil {
		t.Fatal(err)
	}
	// The borrowed handle sees the same variants as the owned one.
	borrowed := must(value.Borrow())
	handle, ok := must(borrowed.Variant()).(ValueChild)
	if !ok || handle.Value == nil {
		t.Fatalf("borrowed Variant() = %#v, want ValueChild", handle)
	}
	if _, err := handle.Value.zigoAcquire("test"); err != nil {
		t.Fatalf("ValueChild.Value is already dead while its parent is open: %v", err)
	}
	handle.Value.zigoRelease()
	if borrowed.MustVariant().(ValueChild).Value == nil {
		t.Fatal("MustVariant() lost the child payload")
	}

	// The child reference the variant carries is parented to the receiver, so
	// closing the union kills it rather than leaving a dangling pointer.
	value.Close()
	if _, err := handle.Value.zigoAcquire("test"); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("ValueChild.Value outlived its parent Value: %v", err)
	}

	// Lifecycle failures stay in Go, and only MustVariant panics.
	if _, err := value.Variant(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Variant() after Close = %v, want ErrInvalidHandle", err)
	}
	assertHandlePanicIn(t, "Value.Tag receiver", func() { value.MustVariant() })
	assertHandlePanicIn(t, "Value.Tag receiver", func() { borrowed.MustVariant() })
}

// assertSignalVariants drives every Signal variant through one type switch.
// Signal is snapshot-backed, so each Variant() call reaches Zig exactly once.
func assertSignalVariants(t *testing.T) {
	t.Helper()

	signal, err := NewSignal(7)
	if err != nil {
		t.Fatal(err)
	}
	defer signal.Close()

	assertVariant[SignalVariant](t, signal, SignalTicks{Value: 7})

	if err := signal.SetLevel(1.5); err != nil {
		t.Fatal(err)
	}
	assertVariant[SignalVariant](t, signal, SignalLevel{Value: 1.5})

	if err := signal.SetOffset(-3); err != nil {
		t.Fatal(err)
	}
	assertVariant[SignalVariant](t, signal, SignalOffset{Value: -3})

	if err := signal.SetMode(ModeActive); err != nil {
		t.Fatal(err)
	}
	assertVariant[SignalVariant](t, signal, SignalMode{Value: ModeActive})

	if err := signal.SetActive(true); err != nil {
		t.Fatal(err)
	}
	assertVariant[SignalVariant](t, signal, SignalActive{Value: true})

	if err := signal.SetIdle(); err != nil {
		t.Fatal(err)
	}
	assertVariant[SignalVariant](t, signal, SignalIdle{})

	// A type switch reads the payload without a second native call.
	if err := signal.SetTicks(11); err != nil {
		t.Fatal(err)
	}
	switch active := must(signal.Variant()).(type) {
	case SignalTicks:
		if active.Value != 11 {
			t.Fatalf("SignalTicks.Value = %d, want 11", active.Value)
		}
	default:
		t.Fatalf("Variant() = %T, want SignalTicks", active)
	}

	// The snapshot and projection surfaces are unchanged by the variant API.
	if got := must(signal.Snapshot()).Tag(); got != SignalTagTicks {
		t.Fatalf("Snapshot().Tag() = %v, want %v", got, SignalTagTicks)
	}
	if got, ok := must2(signal.AsTicks()); !ok || got != 11 {
		t.Fatalf("AsTicks() = (%d, %v), want (11, true)", got, ok)
	}

	signal.Close()
	if _, err := signal.Variant(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Variant() after Close = %v, want ErrInvalidHandle", err)
	}
	assertHandlePanicIn(t, "Signal.Snapshot receiver", func() { signal.MustVariant() })
}

// Every union's owned handle carries the accessor pair. A borrowed
// reference would carry it too, but this example hands none out, so no
// Ref type is generated for either union.
var (
	_ variantReader[ValueVariant]  = (*Value)(nil)
	_ variantReader[SignalVariant] = (*Signal)(nil)
)

// variantReader is the accessor pair every generated union carries.
type variantReader[T comparable] interface {
	Variant() (T, error)
	MustVariant() T
}

func assertVariant[T comparable](t *testing.T, reader variantReader[T], want T) {
	t.Helper()
	if got := must(reader.Variant()); got != want {
		t.Fatalf("Variant() = %#v, want %#v", got, want)
	}
	if got := reader.MustVariant(); got != want {
		t.Fatalf("MustVariant() = %#v, want %#v", got, want)
	}
}

func assertHandlePanicIn(t *testing.T, operation string, call func()) {
	t.Helper()
	defer func() {
		recovered := recover()
		if recovered == nil {
			t.Fatalf("%s did not panic", operation)
		}
		err, ok := recovered.(error)
		if !ok || !errors.Is(err, ErrInvalidHandle) {
			t.Fatalf("%s panic = %#v", operation, recovered)
		}
		var handleErr *HandleError
		if !errors.As(err, &handleErr) || handleErr.Operation != operation {
			t.Fatalf("%s panic error = %#v", operation, err)
		}
	}()
	call()
}

func TestValueVariants(t *testing.T) {
	assertValueVariants(t)
}

func TestSignalVariants(t *testing.T) {
	assertSignalVariants(t)
}
