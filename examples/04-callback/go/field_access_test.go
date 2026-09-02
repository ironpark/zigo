package callback

import "testing"

func TestNestedFieldAccessors(t *testing.T) {
	context, err := NewCallbackContext(func(value int32) (int32, error) { return value, nil })
	if err != nil {
		t.Fatal(err)
	}
	defer context.Close()
	if err := context.SetRunCount(41); err != nil {
		t.Fatal(err)
	}
	if _, err := context.Run(7); err != nil {
		t.Fatal(err)
	}
	got, err := context.RunCount()
	if err != nil {
		t.Fatal(err)
	}
	if got != 42 {
		t.Fatalf("RunCount() = %d, want 42", got)
	}
}
