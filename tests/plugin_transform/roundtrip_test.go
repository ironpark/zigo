package custom

import (
	"os"
	"testing"
	"time"
)

func TestPluginTransform(t *testing.T) {
	if err := loadTestLibrary(os.Getenv("ZIGO_TEST_LIBRARY")); err != nil {
		t.Fatal(err)
	}
	if got := HTTPCombine(time.Unix(7, 0), time.Unix(2, 0)).Unix(); got != 207 {
		t.Fatalf("reordered arguments: got %d, want 207", got)
	}
	if got := HTTPDerived(time.Unix(2, 0), time.Unix(7, 0)).Unix(); got != 207 {
		t.Fatalf("derived wrapper: got %d, want 207", got)
	}
	if got := State(HTTPStateReady); got != HTTPStateReady {
		t.Fatalf("renamed enum: %v", got)
	}
}
