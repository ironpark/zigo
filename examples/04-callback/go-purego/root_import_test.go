package callback_test

import (
	"testing"

	callback "example.com/zigo/callback-purego"
)

func TestModuleRootImport(t *testing.T) {
	if callback.ErrCallbackFailed == nil {
		t.Fatal("root package did not expose generated declarations")
	}
}
