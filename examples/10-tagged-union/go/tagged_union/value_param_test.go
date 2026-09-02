package tagged_union

import "testing"

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
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := ScrollAmount(test.value); got != test.want {
				t.Fatalf("ScrollAmount(%v) = %d, want %d", test.value.Tag(), got, test.want)
			}
		})
	}
}
