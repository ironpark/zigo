package tagged_union

import (
	"errors"
	"testing"
)

func TestTaggedUnionValueParameters(t *testing.T) {
	tests := []struct {
		name  string
		value ScrollViewport
		want  int
	}{
		{"top", ScrollViewportTop(), 1},
		{"bottom", ScrollViewportBottom(), 2},
		{"delta", ScrollViewportDelta(-4), -4},
		{"page", ScrollViewportPage(3), 3},
		{"rgb", ScrollViewportRgb(RGB{R: 5, G: 6, B: 7}), 18},
		{"region", ScrollViewportRegion(Region{Origin: Point{X: 2, Y: 3}, Width: 4}), 9},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := ScrollAmount(test.value); got != test.want {
				t.Fatalf("ScrollAmount(%v) = %d, want %d", test.value.Tag(), got, test.want)
			}
		})
	}
}

func TestTaggedUnionValueReturns(t *testing.T) {
	for kind, want := range []int{18, 9} {
		value, err := CurrentViewport(uint8(kind))
		if err != nil {
			t.Fatalf("CurrentViewport(%d): %v", kind, err)
		}
		if got := ScrollAmount(value); got != want {
			t.Fatalf("round trip %d = %d, want %d", kind, got, want)
		}
	}
	_, err := CurrentViewport(2)
	var nativeErr *Error
	if !errors.As(err, &nativeErr) || nativeErr.Name != "OmittedVariant" {
		t.Fatalf("omitted return error = %#v, want *Error OmittedVariant", err)
	}
}

func TestTaggedUnionValueAccessors(t *testing.T) {
	value, err := CurrentViewport(0)
	if err != nil {
		t.Fatalf("CurrentViewport(0): %v", err)
	}
	rgb, ok := value.AsRgb()
	if !ok || rgb != (RGB{R: 5, G: 6, B: 7}) {
		t.Fatalf("AsRgb() = %v, %v; want {5 6 7}, true", rgb, ok)
	}
	if delta, ok := value.AsDelta(); ok || delta != 0 {
		t.Fatalf("AsDelta() on an rgb value = %d, %v; want 0, false", delta, ok)
	}
	if region, ok := ScrollViewportRegion(Region{Width: 4}).AsRegion(); !ok || region.Width != 4 {
		t.Fatalf("AsRegion() = %v, %v; want width 4, true", region, ok)
	}
}
