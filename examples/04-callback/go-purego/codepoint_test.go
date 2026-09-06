package callback

import "testing"

// The visitor is a plain `func(rune)` even though the native side passes
// `u32`; the generated handle constructor converts the argument.
var _ Visitor = func(cp rune) {}

func TestVisitCodepoints(t *testing.T) {
	var seen []rune
	last := VisitCodepoints([]byte("a\u00e9\U0001F642"), func(cp rune) { seen = append(seen, cp) })
	if string(seen) != "a\u00e9\U0001F642" {
		t.Fatalf("visited %q", string(seen))
	}
	if last != 0x1F642 {
		t.Fatalf("last codepoint = %#x, want U+1F642", last)
	}
}
