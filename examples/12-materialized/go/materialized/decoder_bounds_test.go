package materialized

import (
	contracts "example.com/zigo/runtime-contracts"
	"testing"
)

func TestMaterializedRejectsInvalidArrayRanges(t *testing.T) {
	contracts.ArrayRanges(t, zigoMaterializedArray)
}
func TestMaterializedRejectsRootCountBeforeAllocation(t *testing.T) {
	contracts.RootCounts(t, zigoMaterializedMagicVersion, 1, func(buffer []byte) { zigoDecodeProbeSliceBuffer(buffer) })
}
func TestMaterializedRejectsFieldCountBeforeAllocation(t *testing.T) {
	contracts.FieldCounts(t, zigoMaterializedMagicVersion, 1, 200, []int{24, 40, 56, 96, 152, 168, 184}, func(buffer []byte) { zigoDecodeProbeBuffer(buffer) })
}
func FuzzMaterializedArrayRange(f *testing.F) {
	contracts.FuzzArrayRange(f, zigoMaterializedArray)
}
