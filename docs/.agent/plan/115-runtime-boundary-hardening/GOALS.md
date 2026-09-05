# GOALS

## Problem and the end result from the user's point of view

Preserve reader data and errors and make runtime boundary failures predictable.

## Measurable goals

Both stream backends pass empty-read and data-with-error regressions; materialized allocation failures release partial buffers and invalid counts are rejected before allocation.

## Supported scope and non-goals

Stream generation, materialized serialization/decoding, compiler diagnostics and CI race coverage. No public ABI redesign.

## Reference source / commit / license

Current repository implementation and existing example tests under the repository license.

## Completion criteria for the whole plan

Root tests and affected cgo/purego tests pass with generated outputs synchronized.
