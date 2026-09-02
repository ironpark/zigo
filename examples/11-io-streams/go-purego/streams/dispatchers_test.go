package streams

import "example.com/zigo/streams-purego/internal/raw"

func rawStreamWriterPointer() uintptr { return raw.StreamWriterCallbackPointer() }
func rawStreamReaderPointer() uintptr { return raw.StreamReaderCallbackPointer() }
