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

// countingBuffer is a *bytes.Buffer wearing a counter. Bytes() is what puts
// it on the no-callback fast path, so what the counter records is whether the
// native call ever had to come back into Go for more input.
type countingBuffer struct {
	buffer bytes.Buffer
	reads  int
}

func (b *countingBuffer) Read(p []byte) (int, error) { b.reads++; return b.buffer.Read(p) }
func (b *countingBuffer) Bytes() []byte              { return b.buffer.Bytes() }

// countingReader has no Bytes(), so it is the control: the same payload read
// through the trampoline, which must cost at least one crossing.
type countingReader struct {
	reader io.Reader
	reads  int
}

func (r *countingReader) Read(p []byte) (int, error) { r.reads++; return r.reader.Read(p) }

// zigoBytesReader opts into the fast path with the documented hook rather
// than with Bytes(), which it deliberately does not have.
type zigoBytesReader struct {
	data  []byte
	reads int
}

func (r *zigoBytesReader) Read(p []byte) (int, error) { r.reads++; return 0, io.EOF }
func (r *zigoBytesReader) zigoBytes() []byte          { return r.data }

// The measurable promise of the fast path: a reader that can hand its bytes
// over whole is read by the native side without re-entering Go at all.
func TestBytesReaderCostsNoCallback(t *testing.T) {
	source := &countingBuffer{}
	source.buffer.WriteString("alpha\nbeta\ngamma\n")

	document := newDocumentWithLines(t, nil)
	read, err := document.Load(source)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if read != uint(len("alpha\nbeta\ngamma\n")) {
		t.Fatalf("Load consumed %d bytes", read)
	}
	if source.reads != 0 {
		t.Fatalf("Load cost %d Read calls; a bytes.Buffer must cost none", source.reads)
	}
	count, err := document.Count()
	if err != nil {
		t.Fatalf("Count: %v", err)
	}
	if count != 3 {
		t.Fatalf("Load read %d lines, want 3", count)
	}
}

func TestNonBytesReaderStillCrossesForItsInput(t *testing.T) {
	source := &countingReader{reader: strings.NewReader("alpha\nbeta\n")}
	document := newDocumentWithLines(t, nil)
	if _, err := document.Load(source); err != nil {
		t.Fatalf("Load: %v", err)
	}
	if source.reads == 0 {
		t.Fatal("a reader without Bytes() was not read through the trampoline")
	}
}

// An empty buffer is present-but-empty rather than absent: it takes the fast
// path and ends the stream immediately instead of falling back to callbacks.
func TestEmptyBytesReaderCostsNoCallback(t *testing.T) {
	source := &countingBuffer{}
	document := newDocumentWithLines(t, nil)
	read, err := document.Load(source)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if read != 0 || source.reads != 0 {
		t.Fatalf("Load consumed %d bytes over %d Read calls", read, source.reads)
	}
}

func TestZigoBytesHookOptsIntoTheFastPath(t *testing.T) {
	source := &zigoBytesReader{data: []byte("alpha\nbeta\n")}
	document := newDocumentWithLines(t, nil)
	read, err := document.Load(source)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if read != uint(len(source.data)) || source.reads != 0 {
		t.Fatalf("Load consumed %d bytes over %d Read calls", read, source.reads)
	}
}

// The other direction: Zig hands the stream out and Go gets the interface.
// io.Copy is the whole assertion -- it only compiles if the handle really is
// an io.Writer and an io.Reader.
var (
	_ io.Writer = (*Sink)(nil)
	_ io.Reader = (*Source)(nil)
)

func TestSinkIsAnIoWriter(t *testing.T) {
	sink, err := NewSink()
	if err != nil {
		t.Fatalf("NewSink: %v", err)
	}
	defer sink.Close()

	payload := strings.Repeat("stream me ", 5000)
	written, err := io.Copy(sink, strings.NewReader(payload))
	if err != nil {
		t.Fatalf("io.Copy into the sink: %v", err)
	}
	if written != int64(len(payload)) {
		t.Fatalf("io.Copy wrote %d bytes, want %d", written, len(payload))
	}
	if err := sink.Flush(); err != nil {
		t.Fatalf("Flush: %v", err)
	}
	count, err := sink.Count()
	if err != nil {
		t.Fatalf("Count: %v", err)
	}
	if count != uint(len(payload)) {
		t.Fatalf("the sink holds %d bytes, want %d", count, len(payload))
	}
}

func TestSourceIsAnIoReader(t *testing.T) {
	payload := strings.Repeat("read me 0123456789 ", 3000)
	source, err := NewSource([]byte(payload))
	if err != nil {
		t.Fatalf("NewSource: %v", err)
	}
	defer source.Close()

	var out bytes.Buffer
	read, err := io.Copy(&out, source)
	if err != nil {
		t.Fatalf("io.Copy out of the source: %v", err)
	}
	if read != int64(len(payload)) || out.String() != payload {
		t.Fatalf("io.Copy read %d bytes", read)
	}
	// The end of the stream is io.EOF and stays io.EOF, not a zero-length
	// success the caller would spin on.
	var scratch [8]byte
	if n, err := source.Read(scratch[:]); n != 0 || !errors.Is(err, io.EOF) {
		t.Fatalf("Read past the end returned %d, %v", n, err)
	}
}

// Both directions in one copy, straight from a Zig-owned reader into a
// Zig-owned writer with no Go buffer in between beyond io.Copy's own.
func TestCopyFromSourceToSink(t *testing.T) {
	payload := strings.Repeat("both ways ", 4000)
	source, err := NewSource([]byte(payload))
	if err != nil {
		t.Fatalf("NewSource: %v", err)
	}
	defer source.Close()
	sink, err := NewSink()
	if err != nil {
		t.Fatalf("NewSink: %v", err)
	}
	defer sink.Close()

	copied, err := io.Copy(sink, source)
	if err != nil {
		t.Fatalf("io.Copy: %v", err)
	}
	if copied != int64(len(payload)) {
		t.Fatalf("io.Copy moved %d bytes, want %d", copied, len(payload))
	}
	if err := sink.Flush(); err != nil {
		t.Fatalf("Flush: %v", err)
	}
	count, err := sink.Count()
	if err != nil {
		t.Fatalf("Count: %v", err)
	}
	if count != uint(len(payload)) {
		t.Fatalf("the sink holds %d bytes, want %d", count, len(payload))
	}
}

// The stream is fetched from the object on every operation and never stored,
// so a closed handle refuses exactly like any other method does -- there is no
// dangling `*std.Io.Writer` for it to reach through.
func TestClosedStreamHandleIsRefused(t *testing.T) {
	sink, err := NewSink()
	if err != nil {
		t.Fatalf("NewSink: %v", err)
	}
	sink.Close()
	if _, err := sink.Write([]byte("gone")); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Write after Close returned %v, want ErrInvalidHandle", err)
	}
	if err := sink.Flush(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Flush after Close returned %v, want ErrInvalidHandle", err)
	}

	source, err := NewSource([]byte("gone"))
	if err != nil {
		t.Fatalf("NewSource: %v", err)
	}
	source.Close()
	var scratch [4]byte
	if _, err := source.Read(scratch[:]); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Read after Close returned %v, want ErrInvalidHandle", err)
	}
}
