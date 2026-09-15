package streams

import (
	"os"
	"strings"
	"testing"
)

// The satisfies plugin writes the interface assertion next to the type it
// belongs to. This reads the generated file rather than restating the
// assertion: that Document has the methods is what implements_test.go
// covers, and what is under test here is that the plugin ran at all.
func TestSatisfiesPluginWroteTheAssertion(t *testing.T) {
	source, err := os.ReadFile("streams_handles_gen.go")
	if err != nil {
		t.Fatalf("read generated handles: %v", err)
	}
	for _, assertion := range []string{
		"var _ io.ReadWriteCloser = (*Document)(nil)",
		"var _ Counter = (*Document)(nil)",
	} {
		if !strings.Contains(string(source), assertion) {
			t.Errorf("generated handles do not contain %q; did the satisfies plugin run?", assertion)
		}
	}
}

// The generated interface the claim names. Reading the assertion out of the
// file says the plugin ran; using the handle through the interface is what
// the checked claim is for, so the two tests sit side by side.
func TestDocumentIsACounter(t *testing.T) {
	document, err := NewDocument()
	if err != nil {
		t.Fatalf("new document: %v", err)
	}
	defer document.Close()
	var counter Counter = document
	if _, err := document.WriteString("hello\n"); err != nil {
		t.Fatalf("write: %v", err)
	}
	count, err := counter.Count()
	if err != nil {
		t.Fatalf("count through the interface: %v", err)
	}
	if count != 1 {
		t.Errorf("counter reports %d lines, want 1", count)
	}
}
