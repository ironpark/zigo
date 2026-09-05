package streams

import (
	"bytes"
	"errors"
	"io"
	"testing"
)

type contractReader struct {
	calls int
	read  func(int, []byte) (int, error)
}

func (r *contractReader) Read(p []byte) (int, error) {
	r.calls++
	return r.read(r.calls, p)
}

// Keep this contract suite identical in the cgo and purego modules.
func TestReaderContract(t *testing.T) {
	sentinel := errors.New("data and error")
	cases := []struct {
		name  string
		read  func(int, []byte) (int, error)
		want  string
		err   error
		calls int
	}{
		{"empty-then-data", func(call int, p []byte) (int, error) {
			if call == 1 {
				return 0, nil
			}
			if call == 2 {
				return copy(p, "payload"), nil
			}
			return 0, io.EOF
		}, "payload", nil, 3},
		{"no-progress", func(int, []byte) (int, error) { return 0, nil }, "", io.ErrNoProgress, 100},
		{"data-and-error", func(call int, p []byte) (int, error) {
			if call > 1 {
				t.Fatal("reader called again after terminal error")
			}
			return copy(p, "payload"), sentinel
		}, "", sentinel, 1},
		{"data-and-eof", func(call int, p []byte) (int, error) {
			if call > 1 {
				t.Fatal("reader called again after EOF")
			}
			return copy(p, "payload"), io.EOF
		}, "payload", nil, 1},
		{"negative-count", func(int, []byte) (int, error) { return -1, nil }, "", io.ErrShortBuffer, 1},
		{"excess-count", func(_ int, p []byte) (int, error) { return len(p) + 1, nil }, "", io.ErrShortBuffer, 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := &contractReader{read: tc.read}
			var output bytes.Buffer
			_, err := Tee(r, &output)
			if !errors.Is(err, tc.err) {
				t.Fatalf("error=%v, want %v", err, tc.err)
			}
			// A failed native call need not flush its staged writer bytes.
			if tc.err == nil && output.String() != tc.want {
				t.Fatalf("output=%q, want %q", output.String(), tc.want)
			}
			if r.calls != tc.calls {
				t.Fatalf("calls=%d, want %d", r.calls, tc.calls)
			}
		})
	}
}
