package streams

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

// installDir is the directory `zig build go-lib` installs the shared library
// into. Zig puts a DLL next to the executables and everything else in lib.
func installDir() string {
	if runtime.GOOS == "windows" {
		return "bin"
	}
	return "lib"
}

func init() {
	// An explicit path keeps the test independent of the loader search path;
	// ZIGO_LIBRARY_PATH still wins so the artifact can be installed elsewhere.
	_, file, _, _ := runtime.Caller(0)
	path := os.Getenv("ZIGO_LIBRARY_PATH")
	if path == "" {
		path = filepath.Join(filepath.Dir(file), "..", "..", "zig-out", installDir(), DefaultLibraryName)
	}
	if err := LoadLibrary(path); err != nil {
		panic(err)
	}
}

// The dispatchers are permanent and shared: every stream parameter in the
// binding is called back through the same two, whichever call installed them.
func TestStreamDispatchersArePermanent(t *testing.T) {
	writer := rawStreamWriterPointer()
	reader := rawStreamReaderPointer()
	if writer == 0 || reader == 0 {
		t.Fatalf("stream dispatchers are %d and %d", writer, reader)
	}
	if rawStreamWriterPointer() != writer || rawStreamReaderPointer() != reader {
		t.Fatal("a second call installed different dispatchers")
	}
	if writer == reader {
		t.Fatal("the two directions share one dispatcher")
	}
}
