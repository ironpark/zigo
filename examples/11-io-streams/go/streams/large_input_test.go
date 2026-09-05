package streams

import (
	"bytes"
	"strings"
	"testing"
)

// Larger than both staging buffers: small strings alone miss stalled drains.
func TestTeeLargeInput(t *testing.T) {
	for _, size := range []int{0, 1, 4095, 4096, 65535, 65536, 65537, 262144} {
		input := strings.Repeat("x", size)
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
