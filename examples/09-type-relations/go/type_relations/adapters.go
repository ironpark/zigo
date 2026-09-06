package type_relations

import (
	"image"

	"example.com/zigo/type-relations/internal/raw"
)

// pointToRaw and pointFromRaw are the two halves of the `.go` adapter the
// binding declares for Point: the generated code spells image.Point in its
// API and calls these to cross the raw mirror.
func pointToRaw(p image.Point) raw.PointData {
	return raw.PointData{X: int16(p.X), Y: int16(p.Y)}
}

func pointFromRaw(p raw.PointData) image.Point {
	return image.Point{X: int(p.X), Y: int(p.Y)}
}

// ObjectCount is the adapted result type of LiveObjects: the binding's
// function-level `.go` names these two conversions for the uint result.
type ObjectCount uint

// The adapter contract names both directions even though ObjectCount is only
// ever returned, so the generated code never calls this one.
func objectCountToRaw(count ObjectCount) uint { return uint(count) }

var _ = objectCountToRaw

func objectCountFromRaw(count uint) ObjectCount { return ObjectCount(count) }
