package raw

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestCallbackDispatcherIsPermanentAcrossLoadRetry(t *testing.T) {
	first := CallbackPointer0()
	if first == 0 || CallbackDispatcherCount() != 1 {
		t.Fatal("callback dispatcher was not initialized")
	}
	if err := LoadLibrary(filepath.Join(t.TempDir(), "missing-library")); err == nil {
		t.Fatal("missing library load succeeded")
	}
	if LibraryLoaded() {
		t.Fatal("failed load partially published native bindings")
	}
	if got := CallbackPointer0(); got != first {
		t.Fatal("failed load allocated a replacement callback dispatcher")
	}
	_, file, _, _ := runtime.Caller(0)
	path := os.Getenv("ZIGO_LIBRARY_PATH")
	if path == "" {
		path = filepath.Join(filepath.Dir(file), "..", "..", "..", "zig-out", "lib", DefaultLibraryName)
	}
	if err := LoadLibrary(path); err != nil {
		t.Fatal(err)
	}
	if !LibraryLoaded() || CallbackPointer0() != first {
		t.Fatal("successful retry did not preserve dispatcher and publish atomically")
	}
}
