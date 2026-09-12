package streams

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"strings"
	"testing"
)

// The `.implements` wrappers: Document satisfies the four io interfaces
// through Append, ReadInto, Dump and Load, and each source method is still
// there. Which interface a type satisfies is decided at compile time.
var (
	_ io.Writer       = (*Document)(nil)
	_ io.Reader       = (*Document)(nil)
	_ io.WriterTo     = (*Document)(nil)
	_ io.ReaderFrom   = (*Document)(nil)
	_ io.StringWriter = (*Document)(nil)
)

// io.ReadWriteCloser is not restated here: the satisfies plugin writes that
// assertion into the generated handles file, next to the type it is about.

func TestDocumentIsAnIoWriter(t *testing.T) {
	doc, err := NewDocument()
	if err != nil {
		t.Fatalf("NewDocument: %v", err)
	}
	defer doc.Close()

	// Write takes the whole of p and reports its length: what fmt relies on.
	if _, err := fmt.Fprintf(doc, "line %d", 1); err != nil {
		t.Fatalf("Fprintf: %v", err)
	}
	n, err := io.Copy(doc, strings.NewReader("line 2"))
	if err != nil || n != 6 {
		t.Fatalf("io.Copy wrote %d, %v", n, err)
	}
	count, err := doc.Count()
	if err != nil || count != 2 {
		t.Fatalf("Count = %d, %v", count, err)
	}
}

func TestDocumentWriteToCountsWhatTheWriterReceived(t *testing.T) {
	doc, err := NewDocument()
	if err != nil {
		t.Fatalf("NewDocument: %v", err)
	}
	defer doc.Close()
	for _, line := range []string{"alpha", "beta", "gamma"} {
		if err := doc.Append([]byte(line)); err != nil {
			t.Fatalf("Append: %v", err)
		}
	}

	var out bytes.Buffer
	n, err := doc.WriteTo(&out)
	if err != nil {
		t.Fatalf("WriteTo: %v", err)
	}
	if want := "alpha\nbeta\ngamma\n"; out.String() != want || n != int64(len(want)) {
		t.Fatalf("WriteTo wrote %d bytes %q", n, out.String())
	}
	// Dump returns no count, so WriteTo's is what the writer saw: nothing,
	// when the writer refuses its first crossing, and the writer's own error.
	failing := &failingWriter{err: errors.New("disk full")}
	n, err = doc.WriteTo(failing)
	if !errors.Is(err, failing.err) || n != 0 {
		t.Fatalf("WriteTo into a failing writer: %d, %v", n, err)
	}
}

func TestDocumentReadFromReportsTheLoadedCount(t *testing.T) {
	doc, err := NewDocument()
	if err != nil {
		t.Fatalf("NewDocument: %v", err)
	}
	defer doc.Close()

	n, err := doc.ReadFrom(strings.NewReader("one\ntwo\n"))
	if err != nil || n != 8 {
		t.Fatalf("ReadFrom = %d, %v", n, err)
	}
	count, err := doc.Count()
	if err != nil || count != 2 {
		t.Fatalf("Count = %d, %v", count, err)
	}
}

func TestDocumentIsAnIoReader(t *testing.T) {
	doc, err := NewDocument()
	if err != nil {
		t.Fatalf("NewDocument: %v", err)
	}
	defer doc.Close()
	payload := strings.Repeat("a fairly long line of text\n", 400)
	if _, err := doc.ReadFrom(strings.NewReader(payload)); err != nil {
		t.Fatalf("ReadFrom: %v", err)
	}

	// io.ReadAll drives Read until io.EOF, in whatever chunk sizes it likes.
	data, err := io.ReadAll(doc)
	if err != nil {
		t.Fatalf("io.ReadAll: %v", err)
	}
	if string(data) != payload {
		t.Fatalf("io.ReadAll returned %d bytes, want %d", len(data), len(payload))
	}
	var scratch [8]byte
	if n, err := doc.Read(scratch[:]); n != 0 || !errors.Is(err, io.EOF) {
		t.Fatalf("Read past the end returned %d, %v", n, err)
	}
	// ReadInto is still there, with its own shape.
	if n, err := doc.ReadInto(scratch[:]); n != 0 || err != nil {
		t.Fatalf("ReadInto past the end returned %d, %v", n, err)
	}
}

func TestImplementsWrappersRefuseAClosedHandle(t *testing.T) {
	doc, err := NewDocument()
	if err != nil {
		t.Fatalf("NewDocument: %v", err)
	}
	if err := doc.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	var handleErr *HandleError
	if _, err := doc.Write([]byte("x")); !errors.As(err, &handleErr) {
		t.Fatalf("Write on a closed handle: %v", err)
	}
	if _, err := doc.Read(make([]byte, 4)); !errors.As(err, &handleErr) {
		t.Fatalf("Read on a closed handle: %v", err)
	}
	if _, err := doc.WriteTo(io.Discard); !errors.As(err, &handleErr) {
		t.Fatalf("WriteTo on a closed handle: %v", err)
	}
	if _, err := doc.ReadFrom(strings.NewReader("x\n")); !errors.As(err, &handleErr) {
		t.Fatalf("ReadFrom on a closed handle: %v", err)
	}
}

// WriteString is the string-shaped Write: it hands the Go string to the method
// without a []byte conversion, and reports the length it consumed. io.WriteString
// prefers it over Write when a type has it, which is the point of satisfying it.
func TestDocumentIsAnIoStringWriter(t *testing.T) {
	doc, err := NewDocument()
	if err != nil {
		t.Fatalf("NewDocument: %v", err)
	}
	defer doc.Close()

	n, err := doc.WriteString("alpha")
	if err != nil || n != len("alpha") {
		t.Fatalf("WriteString = %d, %v; want %d, nil", n, err, len("alpha"))
	}
	// io.WriteString routes through WriteString when the target has one.
	if _, err := io.WriteString(doc, "beta"); err != nil {
		t.Fatalf("io.WriteString: %v", err)
	}

	count, err := doc.Count()
	if err != nil || count != 2 {
		t.Fatalf("Count = %d, %v; want 2, nil", count, err)
	}
	var out bytes.Buffer
	if _, err := doc.WriteTo(&out); err != nil {
		t.Fatalf("WriteTo: %v", err)
	}
	if got := out.String(); got != "alpha\nbeta\n" {
		t.Fatalf("document = %q, want %q", got, "alpha\nbeta\n")
	}

	// The bound method is still there under its own name.
	if err := doc.AppendString("gamma"); err != nil {
		t.Fatalf("AppendString: %v", err)
	}
}

// A closed handle reports through the wrapper exactly as it does through the
// method: the wrapper adds no path of its own.
func TestWriteStringOnAClosedDocument(t *testing.T) {
	doc, err := NewDocument()
	if err != nil {
		t.Fatalf("NewDocument: %v", err)
	}
	if err := doc.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	var handleErr *HandleError
	if _, err := doc.WriteString("alpha"); !errors.As(err, &handleErr) {
		t.Fatalf("WriteString after Close = %v, want a HandleError", err)
	}
}
