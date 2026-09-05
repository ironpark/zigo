package contracts

import (
	"bytes"
	"errors"
	"io"
	"strings"
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

// ReaderContract verifies Go reader behavior through a backend's stream bridge.
func ReaderContract(t *testing.T, tee func(io.Reader, io.Writer) (uint, error)) {
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
			_, err := tee(r, &output)
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

// Larger than both staging buffers: small strings alone miss stalled drains.
// LargeInput verifies progress across native staging buffer boundaries.
func LargeInput(t *testing.T, tee func(io.Reader, io.Writer) (uint, error)) {
	for _, size := range []int{0, 1, 4095, 4096, 65535, 65536, 65537, 262144, 1 << 20} {
		input := strings.Repeat("0123456789abcdef!", (size+16)/17)[:size]
		var output bytes.Buffer
		written, err := tee(strings.NewReader(input), &output)
		if err != nil {
			t.Fatal(err)
		}
		if written != uint(size) || output.String() != input {
			t.Fatalf("size %d: count=%d, output length=%d", size, written, output.Len())
		}
	}
}

type largeInputWriter func([]byte) (int, error)

func (w largeInputWriter) Write(p []byte) (int, error) { return w(p) }

type largeInputReader func([]byte) (int, error)

func (r largeInputReader) Read(p []byte) (int, error) { return r(p) }

// FailureAfterFullBuffer verifies terminal failures after partial progress.
func FailureAfterFullBuffer(t *testing.T, tee func(io.Reader, io.Writer) (uint, error)) {
	failed := errors.New("stream failed after making progress")
	input := strings.Repeat("payload", 40000)
	calls := 0
	writer := largeInputWriter(func(p []byte) (int, error) {
		calls++
		if calls >= 2 {
			return 0, failed
		}
		return len(p), nil
	})
	if _, err := tee(strings.NewReader(input), writer); !errors.Is(err, failed) {
		t.Fatalf("writer error = %v, want %v", err, failed)
	}
	if calls != 2 {
		t.Fatalf("writer called %d times, want 2 without retry after failure", calls)
	}
	reader := io.MultiReader(strings.NewReader(input), largeInputReader(func([]byte) (int, error) {
		return 0, failed
	}))
	var output bytes.Buffer
	if _, err := tee(reader, &output); !errors.Is(err, failed) {
		t.Fatalf("reader error = %v, want %v", err, failed)
	}
}
