// Package layoutguard pins the compile-time layout guard that zigo generates
// next to every castable `extern struct`. The types below are a copy of the
// `value_struct` golden with the public field order reversed, which is exactly
// the drift the guard exists to catch: `go build` must reject this package.
//
// Nothing imports it, so it is built on its own by the `test` step.
package layoutguard

import "unsafe"

// Point is the public mirror, with x and y deliberately swapped.
type Point struct {
	Y int16
	X int16
}

// PointData is the raw mirror, in the order the C header declares.
type PointData struct {
	X int16
	Y int16
}

var _ = [1]struct{}{}[unsafe.Sizeof(Point{})-unsafe.Sizeof(PointData{})]
var _ = [1]struct{}{}[unsafe.Offsetof(Point{}.X)-unsafe.Offsetof(PointData{}.X)]
var _ = [1]struct{}{}[unsafe.Offsetof(Point{}.Y)-unsafe.Offsetof(PointData{}.Y)]
