package palette

import (
	"encoding/json"
	"testing"
)

func TestJSONCodepointRoundTrip(t *testing.T) {
	for _, point := range []rune{0, '한', '😀', 0x10ffff} {
		value := Color{Red: 12, Green: 34, Codepoint: point}
		data, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		var wire map[string]int64
		if err := json.Unmarshal(data, &wire); err != nil {
			t.Fatal(err)
		}
		if wire["codepoint"] != int64(point) {
			t.Fatalf("codepoint key changed: %s", data)
		}
		var decoded Color
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatal(err)
		}
		if decoded != value {
			t.Fatalf("got %+v, want %+v", decoded, value)
		}
	}
}
