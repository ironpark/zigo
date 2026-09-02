package tagged_union

import "testing"

func assertTaggedUnionValueParameters(t *testing.T) {
	t.Helper()
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
