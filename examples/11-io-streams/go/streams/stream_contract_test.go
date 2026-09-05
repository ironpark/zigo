package streams

import (
	contracts "example.com/zigo/runtime-contracts"
	"testing"
)

func TestReaderContract(t *testing.T)            { contracts.ReaderContract(t, Tee) }
func TestTeeLargeInput(t *testing.T)             { contracts.LargeInput(t, Tee) }
func TestTeeFailureAfterFullBuffer(t *testing.T) { contracts.FailureAfterFullBuffer(t, Tee) }
