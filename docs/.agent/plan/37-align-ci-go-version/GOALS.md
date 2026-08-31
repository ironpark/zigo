# GOALS

## Problem and the end result from the user's point of view

CI installs Go 1.24 with local toolchain selection, but two example modules require Go 1.26 and therefore fail before tests run.

## Measurable goals

- Every example module requires Go 1.24 or earlier.
- The scalar and errors example modules declare `go 1.24`.
- Their Go tests pass after the version correction.

## Supported scope and non-goals

Correct the two inconsistent `go.mod` directives only. Do not upgrade CI or alter generated bindings and unrelated in-progress work.

## Reference source / commit / license

Use `.github/workflows/ci.yml` and the repository documentation that states generated modules target Go 1.24.

## Completion criteria for the whole plan

No example module requires a Go version newer than CI, relevant tests pass, and the fix is committed independently.
