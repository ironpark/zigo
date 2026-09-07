package tagged_union

import (
	"encoding/json"
	"testing"
)

// The json plugin writes MarshalJSON/UnmarshalJSON next to the type. The
// point of the pair is that neither spelling is Go's default: the struct
// keys are the Zig field names, and the enum is its tag name rather than
// the number the Go type is.
func TestJSONPluginEncodesValueStructUnderZigFieldNames(t *testing.T) {
	encoded, err := json.Marshal(RGB{R: 1, G: 2, B: 3})
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if string(encoded) != `{"r":1,"g":2,"b":3}` {
		t.Fatalf("Marshal = %s, want the Zig field names", encoded)
	}

	var decoded RGB
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if decoded != (RGB{R: 1, G: 2, B: 3}) {
		t.Fatalf("Unmarshal = %+v, want the value that was encoded", decoded)
	}
}

func TestJSONPluginEncodesEnumAsItsZigTagName(t *testing.T) {
	encoded, err := json.Marshal(ModePaused)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if string(encoded) != `"paused"` {
		t.Fatalf("Marshal = %s, want the Zig tag name", encoded)
	}

	var decoded Mode
	if err := json.Unmarshal([]byte(`"active"`), &decoded); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if decoded != ModeActive {
		t.Fatalf("Unmarshal = %v, want ModeActive", decoded)
	}

	// A tag this build does not have is an error rather than a zero value:
	// silently becoming the first constant is how wire bugs stay hidden.
	if err := json.Unmarshal([]byte(`"retired"`), &decoded); err == nil {
		t.Fatal("Unmarshal of an unknown tag succeeded")
	}
}
