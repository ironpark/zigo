// Package cheader reports the C struct layout the generated header defines.
// cgo cannot be used from a _test.go file, so the sizes and offsets the layout
// test compares against are read here and exported as plain Go values.
package cheader

/*
#cgo CFLAGS: -I${SRCDIR}/../../../../zig-out/include
#include <stddef.h>
#include "zigo_event_queue.h"

static const size_t offsetof_stats_len = offsetof(zg_stats, len);
static const size_t offsetof_stats_capacity = offsetof(zg_stats, capacity);
static const size_t offsetof_stats_dropped = offsetof(zg_stats, dropped);
static const size_t offsetof_stats_processed = offsetof(zg_stats, processed);
static const size_t offsetof_stats_policy = offsetof(zg_stats, policy);
static const size_t offsetof_stats_saturated = offsetof(zg_stats, saturated);
static const size_t offsetof_limits_capacity = offsetof(zg_limits, capacity);
static const size_t offsetof_limits_policy = offsetof(zg_limits, policy);
*/
import "C"

import "unsafe"

// StatsSize is sizeof(zg_stats).
var StatsSize = unsafe.Sizeof(C.zg_stats{})

// StatsOffsets maps each zg_stats member to its byte offset.
var StatsOffsets = map[string]uintptr{
	"len":       uintptr(C.offsetof_stats_len),
	"capacity":  uintptr(C.offsetof_stats_capacity),
	"dropped":   uintptr(C.offsetof_stats_dropped),
	"processed": uintptr(C.offsetof_stats_processed),
	"policy":    uintptr(C.offsetof_stats_policy),
	"saturated": uintptr(C.offsetof_stats_saturated),
}

// LimitsSize is sizeof(zg_limits).
var LimitsSize = unsafe.Sizeof(C.zg_limits{})

// LimitsOffsets maps each zg_limits member to its byte offset.
var LimitsOffsets = map[string]uintptr{
	"capacity": uintptr(C.offsetof_limits_capacity),
	"policy":   uintptr(C.offsetof_limits_policy),
}
