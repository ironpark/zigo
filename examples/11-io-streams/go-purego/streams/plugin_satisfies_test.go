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
	const assertion = "var _ io.ReadWriteCloser = (*Document)(nil)"
	if !strings.Contains(string(source), assertion) {
		t.Errorf("generated handles do not contain %q; did the satisfies plugin run?", assertion)
	}
}
