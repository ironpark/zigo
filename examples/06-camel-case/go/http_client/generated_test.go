package http_client

import "testing"

func TestStatusCode(t *testing.T) {
	if got := StatusCode(3); got != 203 {
		t.Fatalf("StatusCode(3) = %d, want 203", got)
	}
}
