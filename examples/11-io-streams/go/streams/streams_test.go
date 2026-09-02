package streams

import (
	"bytes"
	"errors"
	"io"
	"strings"
	"testing"
)

// countingWriter is what makes the staging buffer visible: it records the size
// of every crossing, so a test can assert that a payload costs one Write per
// buffer rather than one per Zig writeAll.
type countingWriter struct {
	sink   bytes.Buffer
	writes []int
}

func (w *countingWriter) Write(p []byte) (int, error) {
	w.writes = append(w.writes, len(p))
	return w.sink.Write(p)
}

type failingWriter struct {
	after int
	err   error
}

func (w *failingWriter) Write(p []byte) (int, error) {
	if w.after <= 0 {
		return 0, w.err
	}
	w.after--
	return len(p), nil
}

type panickingWriter struct{}

func (panickingWriter) Write([]byte) (int, error) { panic("writer exploded") }

type failingReader struct{ err error }

func (r failingReader) Read([]byte) (int, error) { return 0, r.err }

func newDocumentWithLines(t *testing.T, lines []string) *Document {
	t.Helper()
	document, err := NewDocument()
	if err != nil {
		t.Fatalf("NewDocument: %v", err)
	}
	t.Cleanup(func() { document.Close() })
	for _, line := range lines {
		if err := document.Append([]byte(line)); err != nil {
			t.Fatalf("Append(%q): %v", line, err)
		}
	}
	return document
}

func TestDumpAndLoadRoundTrip(t *testing.T) {
	document := newDocumentWithLines(t, []string{"alpha", "beta", "gamma"})

	var buffer bytes.Buffer
	if err := document.Dump(&buffer); err != nil {
		t.Fatalf("Dump: %v", err)
	}
	if got := buffer.String(); got != "alpha\nbeta\ngamma\n" {
		t.Fatalf("Dump wrote %q", got)
	}

	restored := newDocumentWithLines(t, nil)
	read, err := restored.Load(bytes.NewReader(buffer.Bytes()))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if read != uint(buffer.Len()) {
		t.Fatalf("Load consumed %d bytes, wrote %d", read, buffer.Len())
	}
	count, err := restored.Count()
	if err != nil {
		t.Fatalf("Count: %v", err)
	}
	if count != 3 {
		t.Fatalf("restored %d lines, want 3", count)
	}
}

// The measurable promise of the staging buffer: a payload far larger than it
// costs at most one crossing per buffer, not one per Zig write.
func TestDumpCrossesOncePerBuffer(t *testing.T) {
	const bufferBytes = 65536
	const lines = 20000
	const lineBytes = 40

	document := newDocumentWithLines(t, nil)
	line := bytes.Repeat([]byte("x"), lineBytes-1)
	for i := 0; i < lines; i++ {
		if err := document.Append(line); err != nil {
			t.Fatalf("Append: %v", err)
		}
	}

	writer := &countingWriter{}
	if err := document.Dump(writer); err != nil {
		t.Fatalf("Dump: %v", err)
	}

	total := lines * lineBytes
	if writer.sink.Len() != total {
		t.Fatalf("Dump wrote %d bytes, want %d", writer.sink.Len(), total)
	}
	ceiling := (total + bufferBytes - 1) / bufferBytes
	if len(writer.writes) > ceiling {
		t.Fatalf("Dump cost %d Write calls for %d bytes; at most %d expected", len(writer.writes), total, ceiling)
	}
	// And it is a real streaming path rather than one giant crossing: the Zig
	// side called writeAll twice per line and the boundary saw far fewer.
	if len(writer.writes) < 2 {
		t.Fatalf("Dump cost %d Write calls; the payload is larger than the buffer", len(writer.writes))
	}
}

func TestWriterErrorIsReturnedAndIdentifiable(t *testing.T) {
	document := newDocumentWithLines(t, []string{"alpha", "beta"})
	sentinel := errors.New("disk on fire")

	err := document.Dump(&failingWriter{err: sentinel})
	if err == nil {
		t.Fatal("Dump returned no error for a failing writer")
	}
	if !errors.Is(err, sentinel) {
		t.Fatalf("Dump error %v does not wrap the writer's own error", err)
	}
	var streamErr *StreamError
	if !errors.As(err, &streamErr) {
		t.Fatalf("Dump error %v is not a *StreamError", err)
	}
	if streamErr.Operation != "Document.Dump" || streamErr.Parameter != "w" {
		t.Fatalf("StreamError names %q/%q", streamErr.Operation, streamErr.Parameter)
	}
}

func TestWriterPanicIsRethrownAsCallbackPanic(t *testing.T) {
	document := newDocumentWithLines(t, []string{"alpha"})
	defer func() {
		value := recover()
		if value == nil {
			t.Fatal("a panicking writer did not reach the caller")
		}
		err, ok := value.(error)
		if !ok || !errors.Is(err, ErrCallbackPanic) {
			t.Fatalf("recovered %v, want an ErrCallbackPanic", value)
		}
	}()
	_ = document.Dump(panickingWriter{})
}

func TestNilStreamIsAnArgumentError(t *testing.T) {
	document := newDocumentWithLines(t, nil)
	err := document.Dump(nil)
	if !errors.Is(err, ErrNilStream) {
		t.Fatalf("Dump(nil) returned %v, want ErrNilStream", err)
	}
	if _, err := document.Load(nil); !errors.Is(err, ErrNilStream) {
		t.Fatalf("Load(nil) returned %v, want ErrNilStream", err)
	}
}

func TestReaderEndOfStreamStopsTheLoad(t *testing.T) {
	document := newDocumentWithLines(t, nil)
	// io.LimitReader cuts the input short, so the load ends at the limit
	// rather than at the end of the underlying reader.
	source := strings.NewReader("alpha\nbeta\ngamma\n")
	read, err := document.Load(io.LimitReader(source, int64(len("alpha\nbeta\n"))))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if read != uint(len("alpha\nbeta\n")) {
		t.Fatalf("Load consumed %d bytes", read)
	}
	count, err := document.Count()
	if err != nil {
		t.Fatalf("Count: %v", err)
	}
	if count != 2 {
		t.Fatalf("Load read %d lines, want 2", count)
	}
}

func TestReaderErrorIsReturnedAndIdentifiable(t *testing.T) {
	document := newDocumentWithLines(t, nil)
	sentinel := errors.New("cable unplugged")
	_, err := document.Load(failingReader{err: sentinel})
	if !errors.Is(err, sentinel) {
		t.Fatalf("Load error %v does not wrap the reader's own error", err)
	}
}

// Tee has both directions in one call, so it also pins that the two handles
// are independent: only the one that failed reports.
func TestTeeStreamsBothDirections(t *testing.T) {
	var out bytes.Buffer
	written, err := Tee(strings.NewReader("hello stream"), &out)
	if err != nil {
		t.Fatalf("Tee: %v", err)
	}
	if written != uint(len("hello stream")) || out.String() != "hello stream" {
		t.Fatalf("Tee copied %d bytes as %q", written, out.String())
	}

	sentinel := errors.New("sink closed")
	if _, err := Tee(strings.NewReader("hello"), &failingWriter{err: sentinel}); !errors.Is(err, sentinel) {
		t.Fatalf("Tee error %v does not wrap the writer's own error", err)
	}
}

func TestBannerWritesThroughAFreeFunction(t *testing.T) {
	var out bytes.Buffer
	if err := Banner(&out, 8); err != nil {
		t.Fatalf("Banner: %v", err)
	}
	if out.String() != "========\n" {
		t.Fatalf("Banner wrote %q", out.String())
	}
}

// Every call is call-scoped, so no handle may outlive it.
func TestStreamHandlesAreReleased(t *testing.T) {
	document := newDocumentWithLines(t, []string{"alpha"})
	var out bytes.Buffer
	if err := document.Dump(&out); err != nil {
		t.Fatalf("Dump: %v", err)
	}
	if live := activeCallbackHandleCount(); live != 0 {
		t.Fatalf("%d stream handles outlived the call", live)
	}
}
