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
