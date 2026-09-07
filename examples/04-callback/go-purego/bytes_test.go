package callback

import (
	"bytes"
	"testing"
)

// A `[*:0]const u8` and a `[*]const u8` + `usize` pair in the native signature
// are each one Go `string`; the generated trampoline copies the bytes before
// the callback runs, so the strings stay valid after it returns.
var _ Logger = func(level, message string) {}

// The same pair marked `.opaque_bytes` is a `[]byte` copy.
var _ ByteSink = func(chunk []byte) {}

func TestStringCallbackPayloads(t *testing.T) {
	var lines []string
	LogMessage([]byte("héllo"), func(level, message string) {
		lines = append(lines, level+": "+message)
	})
	if len(lines) != 2 || lines[0] != "info: héllo" || lines[1] != "debug: héllo" {
		t.Fatalf("logged %q", lines)
	}
}

func TestByteCallbackPayloads(t *testing.T) {
	var chunks [][]byte
	count := EmitChunks([]byte("abcdefg"), 3, func(chunk []byte) {
		chunks = append(chunks, chunk)
	})
	if count != 3 {
		t.Fatalf("EmitChunks = %d chunks, want 3", count)
	}
	// Each chunk is its own copy: mutating one does not touch the others or
	// the native buffer the next chunk was read from.
	chunks[0][0] = 'z'
	if !bytes.Equal(bytes.Join(chunks, nil), []byte("zbcdefg")) {
		t.Fatalf("chunks = %q", chunks)
	}
}
