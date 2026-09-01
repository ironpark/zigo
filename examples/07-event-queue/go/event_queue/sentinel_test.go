package event_queue

import "testing"

func TestSentinelCString(t *testing.T) {
	const text = "안녕, sentinel"
	if got := EchoCString(text); got != text {
		t.Fatalf("EchoCString() = %q, want %q", got, text)
	}
	if got := SampleCString(); got != "sentinel event queue" {
		t.Fatalf("SampleCString() = %q, want sentinel event queue", got)
	}
}

func TestStringSliceParameters(t *testing.T) {
	paths := []string{"alpha", "", "beta"}
	const want = 9
	for name, extract := range map[string]func([]string) uint{
		"plain": ExtractPaths,
		"slice": ExtractSentinelSlices,
		"many":  ExtractSentinelPointers,
	} {
		if got := extract(paths); got != want {
			t.Errorf("%s extract = %d, want %d", name, got, want)
		}
		if got := extract([]string{}); got != 0 {
			t.Errorf("%s empty extract = %d, want 0", name, got)
		}
	}
}
