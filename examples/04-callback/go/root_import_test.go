package callback_test

import (
	"testing"

	callback "example.com/zigo/callback"
)

// This hand-written root file is also a cleanup sentinel: `zig build go` must
// preserve it and the neighboring go.mod while pruning stale generated files.
func TestModuleRootImport(t *testing.T) {
	if callback.ErrCallbackFailed == nil {
		t.Fatal("root package did not expose generated declarations")
	}
}
