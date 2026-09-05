package main

import (
	"bytes"
	"errors"
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	for _, input := range []string{"", "unterminated", "첫 줄\nsecond line\n", strings.Repeat("large payload\n", 20000)} {
		var output bytes.Buffer
		if err := run(strings.NewReader(input), &output); err != nil {
			t.Fatal(err)
		}
		if output.String() != input {
			t.Fatalf("copied %d bytes, want %d exact bytes", output.Len(), len(input))
		}
	}
}

type failingWriter struct{ err error }

func (w failingWriter) Write([]byte) (int, error) { return 0, w.err }

type failingReader struct{ err error }

func (r failingReader) Read([]byte) (int, error) { return 0, r.err }

func TestRunPreservesErrors(t *testing.T) {
	failed := errors.New("I/O unavailable")
	if err := run(strings.NewReader("payload"), failingWriter{failed}); !errors.Is(err, failed) {
		t.Fatalf("writer error = %v, want %v", err, failed)
	}
	if err := run(failingReader{failed}, &bytes.Buffer{}); !errors.Is(err, failed) {
		t.Fatalf("reader error = %v, want %v", err, failed)
	}
}
