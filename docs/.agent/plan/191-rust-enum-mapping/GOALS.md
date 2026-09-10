# GOALS

## Problem and the end result from the user's point of view
Registered enums must remain named types in Rust parameters and results instead of ZIGO060 or silent integer degradation.

## Measurable goals
Closed and open scalar enums compile warning-free, invalid closed tags never become invalid Rust discriminants, and all existing Go output remains byte-identical. Audit baseline: accepted=7 broken= crashed=.

## Supported scope and non-goals
Scalar enum inputs, direct outputs, status-channel payloads, and handle methods using those values. Closed enums use repr integers and checked conversion. Open enums preserve unnamed values in transparent newtypes. Text opts into Display and FromStr. Enum receivers, enum slices/buffers, tagged unions, namespaces, plugins and cancellation remain diagnosed, outside this implementation.

## Reference source / commit / license
Branch rust-enum-mapping from rust-handles-and-buffers at 4c6db7a6, following the user's corrected instruction. Read plans 186, 188, 189, 190 and rust-target-feasibility; use existing AbiEnum and liveFields. No external code copied.

## Completion criteria for the whole plan
Each phase independently verified, committed and done. Full root and 14-example checks pass; fresh-generator audit has zero broken and crashed documents; changelog and research handoff updated. No push, PR or changes to existing branch refs.
