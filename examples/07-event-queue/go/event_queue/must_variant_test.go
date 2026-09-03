package event_queue

import "testing"

func TestMustVariantPanicsWithTypedHandleError(t *testing.T) {
	queue := MustNewEventQueue("must", 1, PolicyReject, func(uint64, int32) int32 { return 0 })
	if err := queue.Close(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		value := recover()
		handleErr, ok := value.(*HandleError)
		if !ok {
			t.Fatalf("panic value = %T(%v), want *HandleError", value, value)
		}
		if handleErr.Operation != "EventQueue.Len receiver" {
			t.Fatalf("panic operation = %q, want EventQueue.Len receiver", handleErr.Operation)
		}
	}()
	_ = queue.MustLen()
}
