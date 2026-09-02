package type_relations

import (
	"io"
	"testing"
)

// Generated handles close like any other Go resource.
var (
	_ io.Closer = (*Counter)(nil)
	_ io.Closer = (*Accumulator)(nil)
)

// must unwraps a generated call whose only failure mode here would be a nil or
// closed handle.
func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

func TestAccumulatorAcceptsCounter(t *testing.T) {
	counter, err := NewCounter(40)
	if err != nil {
		t.Fatal(err)
	}
	defer counter.Close()

	accumulator, err := NewAccumulator()
	if err != nil {
		t.Fatal(err)
	}
	defer accumulator.Close()

	if got := must(accumulator.Absorb(counter)); got != 40 {
		t.Fatalf("Absorb(counter) = %d, want 40", got)
	}
	if got := must(counter.Add(2)); got != 42 {
		t.Fatalf("counter.Add(2) = %d, want 42", got)
	}
	if got := must(accumulator.Absorb(counter)); got != 82 {
		t.Fatalf("second Absorb(counter) = %d, want 82", got)
	}
}

func TestIndependentLifecycles(t *testing.T) {
	counter, err := NewCounter(1)
	if err != nil {
		t.Fatal(err)
	}
	accumulator, err := NewAccumulator()
	if err != nil {
		t.Fatal(err)
	}

	accumulator.Close()
	accumulator.Close()
	counter.Close()
	counter.Close()
	if got := LiveObjects(); got != 0 {
		t.Fatalf("LiveObjects() = %d, want 0", got)
	}
}

// The binding reaches these through `root.text.runWidth` and
// `root.text.unicode.codepointWidth`, so the nested namespaces cross the
// boundary without a hand-written flattening facade in Zig.
func TestNestedNamespaces(t *testing.T) {
	if got, err := CodepointWidth(0x1100); err != nil || got != 2 {
		t.Fatalf("CodepointWidth(0x1100) = %d, %v, want 2, nil", got, err)
	}
	if got, err := RunWidth(0x1100, 'a'); err != nil || got != 3 {
		t.Fatalf("RunWidth(0x1100, 'a') = %d, %v, want 3, nil", got, err)
	}
}

// The Zig enum was built by a comptime function, so it has no name of its own:
// `@typeName` ends in the slice expression that produced it. The binding
// registered it with `.name = "CursorStyle"`, which is the only reason a Go
// type by that name exists at all.
func TestRegisteredEnum(t *testing.T) {
	if got := DefaultCursorStyle(); got != CursorStyleBlock {
		t.Fatalf("DefaultCursorStyle() = %v, want CursorStyleBlock", got)
	}
	if got := CursorStyleBar.String(); got != "bar" {
		t.Fatalf("CursorStyleBar.String() = %q, want \"bar\"", got)
	}
	if !CursorStyleBlinks(CursorStyleUnderline) || CursorStyleBlinks(CursorStyleBlock) {
		t.Fatal("CursorStyleBlinks disagrees with the Zig function")
	}
	if !ConfigureStyles(CharsetSlotBlock, CursorStyleBar) {
		t.Fatal("ConfigureStyles did not preserve the two distinct generated enum types")
	}
	if !IsWideColumns(DeccolmMode132Cols) || IsWideColumns(DeccolmMode80Cols) {
		t.Fatal("numeric-leading enum tags did not preserve their values")
	}
}

func TestOpenEnumRoundTrip(t *testing.T) {
	unknown := EraseDisplay(42)
	if got := EchoEraseDisplay(unknown); got != unknown {
		t.Fatalf("EchoEraseDisplay(42) = %d, want 42", got)
	}
	if got := unknown.String(); got != "EraseDisplay(42)" {
		t.Fatalf("EraseDisplay(42).String() = %q, want %q", got, "EraseDisplay(42)")
	}
}

// A `?T` parameter is a Go pointer: nil is the Zig `null`, and a non-nil one
// carries the value. A `?T` return is a value plus a presence flag, so an
// absent result is never confused with a zero one.
func TestOptionalScalars(t *testing.T) {
	value := uint32(21)
	if got, ok := DoubleWidth(&value); !ok || got != 42 {
		t.Fatalf("DoubleWidth(21) = %d, %v, want 42, true", got, ok)
	}
	// A present zero is still present: the flag, not the value, says so.
	zero := uint32(0)
	if got, ok := DoubleWidth(&zero); !ok || got != 0 {
		t.Fatalf("DoubleWidth(0) = %d, %v, want 0, true", got, ok)
	}
	if got, ok := DoubleWidth(nil); ok {
		t.Fatalf("DoubleWidth(nil) = %d, %v, want _, false", got, ok)
	}

	flag := true
	if got, ok := Invert(&flag); !ok || got {
		t.Fatalf("Invert(true) = %v, %v, want false, true", got, ok)
	}
	if got, ok := Invert(nil); ok {
		t.Fatalf("Invert(nil) = %v, %v, want _, false", got, ok)
	}
}

// An optional enum keeps its Go enum type on both sides of the boundary.
func TestOptionalEnum(t *testing.T) {
	if got := StyleOrDefault(nil); got != CursorStyleBlock {
		t.Fatalf("StyleOrDefault(nil) = %v, want CursorStyleBlock", got)
	}
	style := CursorStyleBar
	if got := StyleOrDefault(&style); got != CursorStyleBar {
		t.Fatalf("StyleOrDefault(bar) = %v, want CursorStyleBar", got)
	}
	if got, ok := BlinkingStyle(&style); !ok || got != CursorStyleBar {
		t.Fatalf("BlinkingStyle(bar) = %v, %v, want CursorStyleBar, true", got, ok)
	}
	block := CursorStyleBlock
	if _, ok := BlinkingStyle(&block); ok {
		t.Fatal("BlinkingStyle(block) reported a value, want absent")
	}
	if _, ok := BlinkingStyle(nil); ok {
		t.Fatal("BlinkingStyle(nil) reported a value, want absent")
	}
}

// A whole extern struct crosses behind one nullable pointer, and an error
// union over it keeps the error and the absence apart.
func TestOptionalStruct(t *testing.T) {
	origin := Point{X: 1, Y: 2}
	if got, ok := ShiftPoint(&origin, 2); !ok || got != (Point{X: 3, Y: 4}) {
		t.Fatalf("ShiftPoint({1,2}, 2) = %+v, %v, want {3,4}, true", got, ok)
	}
	if _, ok := ShiftPoint(nil, 2); ok {
		t.Fatal("ShiftPoint(nil, 2) reported a value, want absent")
	}

	got, ok, err := CheckedShift(&origin, 1)
	if err != nil || !ok || got != (Point{X: 2, Y: 3}) {
		t.Fatalf("CheckedShift({1,2}, 1) = %+v, %v, %v, want {2,3}, true, nil", got, ok, err)
	}
	// Absent is not an error: the code is 0 and only the flag is false.
	if _, ok, err := CheckedShift(nil, 1); err != nil || ok {
		t.Fatalf("CheckedShift(nil, 1) = _, %v, %v, want false, nil", ok, err)
	}
	if _, _, err := CheckedShift(&origin, 2000); err == nil {
		t.Fatal("CheckedShift({1,2}, 2000) returned no error, want Overflow")
	}
}

// An optional slice is a Go pointer to the slice or string, which is the only
// spelling that separates "no argument" from "an empty one": both a nil and an
// empty `[]byte` would otherwise cross as the same thing.
func TestOptionalSliceParameters(t *testing.T) {
	if got := DescribeText(nil); got != 0 {
		t.Fatalf("DescribeText(nil) = %d, want 0", got)
	}
	empty := ""
	if got := DescribeText(&empty); got != 1 {
		t.Fatalf("DescribeText(&\"\") = %d, want 1", got)
	}
	text := "hi"
	if got := DescribeText(&text); got != 2 {
		t.Fatalf("DescribeText(&\"hi\") = %d, want 2", got)
	}

	if got := SumOrZero(nil); got != -1 {
		t.Fatalf("SumOrZero(nil) = %d, want -1", got)
	}
	none := []int32{}
	if got := SumOrZero(&none); got != 0 {
		t.Fatalf("SumOrZero(&[]) = %d, want 0", got)
	}
	values := []int32{1, 2, 3}
	if got := SumOrZero(&values); got != 6 {
		t.Fatalf("SumOrZero(&[1,2,3]) = %d, want 6", got)
	}
}

// A `?[]T` return is a slice plus a presence flag, so an absent result and an
// empty one are told apart by the flag rather than by the length.
func TestOptionalSliceReturns(t *testing.T) {
	if got, ok := LeadingDigits(3); !ok || len(got) != 3 || got[2] != 2 {
		t.Fatalf("LeadingDigits(3) = %v, %v, want [0 1 2], true", got, ok)
	}
	if got, ok := LeadingDigits(0); !ok || len(got) != 0 {
		t.Fatalf("LeadingDigits(0) = %v, %v, want empty, true", got, ok)
	}
	if got, ok := LeadingDigits(99); ok {
		t.Fatalf("LeadingDigits(99) = %v, %v, want _, false", got, ok)
	}

	style := CursorStyleBar
	if got, ok := StyleName(&style); !ok || got != "bar" {
		t.Fatalf("StyleName(bar) = %q, %v, want \"bar\", true", got, ok)
	}
	if _, ok := StyleName(nil); ok {
		t.Fatal("StyleName(nil) reported a value, want absent")
	}
}
