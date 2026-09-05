package event_queue

import (
	"encoding/json"
	"errors"
	"testing"

	eventtypes "example.com/zigo/event-queue/event_queue/types"
)

func TestQueueSignalTextRoundTrip(t *testing.T) {
	for _, value := range []eventtypes.QueueSignal{
		eventtypes.QueueSignalPause,
		eventtypes.QueueSignalContinueProcessing,
		eventtypes.QueueSignal(42),
	} {
		parsed, err := eventtypes.ParseQueueSignal(value.String())
		if err != nil {
			t.Fatalf("ParseQueueSignal(%q): %v", value.String(), err)
		}
		if parsed != value {
			t.Fatalf("ParseQueueSignal(%q) = %v, want %v", value.String(), parsed, value)
		}
	}
}

func TestQueueSignalJSON(t *testing.T) {
	type payload struct {
		Signal eventtypes.QueueSignal `json:"signal"`
	}
	encoded, err := json.Marshal(payload{Signal: eventtypes.QueueSignalContinueProcessing})
	if err != nil {
		t.Fatal(err)
	}
	if string(encoded) != `{"signal":"continue_processing"}` {
		t.Fatalf("json.Marshal() = %s", encoded)
	}
	var decoded payload
	if err := json.Unmarshal([]byte(`{"signal":"pause"}`), &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded.Signal != eventtypes.QueueSignalPause {
		t.Fatalf("decoded signal = %v, want pause", decoded.Signal)
	}
}

func TestQueueSignalParseRejectsUnknownText(t *testing.T) {
	for _, text := range []string{"", "PAUSE", "QueueSignal(300)", "QueueSignal(x)"} {
		_, err := eventtypes.ParseQueueSignal(text)
		var parseErr *eventtypes.EnumParseError
		if !errors.As(err, &parseErr) {
			t.Fatalf("ParseQueueSignal(%q) error = %v, want *EnumParseError", text, err)
		}
		if parseErr.Type != "QueueSignal" || parseErr.Text != text {
			t.Fatalf("ParseQueueSignal(%q) error = %+v", text, parseErr)
		}
	}
}
