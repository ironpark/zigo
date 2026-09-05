package streams

import (
	"bytes"
	"errors"
	"io"
	"strings"
	"testing"
)

// Larger than both staging buffers: small strings alone miss stalled drains.
func TestTeeLargeInput(t *testing.T) {
	for _, size := range []int{0, 1, 4095, 4096, 65535, 65536, 65537, 262144, 1 << 20} {
		input := strings.Repeat("0123456789abcdef!", (size+16)/17)[:size]
		var output bytes.Buffer
		written, err := Tee(strings.NewReader(input), &output)
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

func TestTeeFailureAfterFullBuffer(t *testing.T) {
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
	if _, err := Tee(strings.NewReader(input), writer); !errors.Is(err, failed) {
		t.Fatalf("writer error = %v, want %v", err, failed)
	}
	if calls != 2 {
		t.Fatalf("writer called %d times, want 2 without retry after failure", calls)
	}
	reader := io.MultiReader(strings.NewReader(input), largeInputReader(func([]byte) (int, error) {
		return 0, failed
	}))
	var output bytes.Buffer
	if _, err := Tee(reader, &output); !errors.Is(err, failed) {
		t.Fatalf("reader error = %v, want %v", err, failed)
	}
}
