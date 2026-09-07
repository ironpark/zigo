# GOALS

## Problem and the end result from the user's point of view

Implement all six findings in the authoring ergonomics review so examples demonstrate the new API clearly.

## Measurable goals

Add typed parameter/result constructors and member composition, explicit contextual constructor receivers, sparse native callback indices and consistent failure naming. Remove redundant source-name overrides and restructure all examples without changing their exported behavior.

## Supported scope and non-goals

Implement the accepted review. No release or push. Preserve one authoring schema and existing runtime lifetime semantics. No speculative name-based selectors or second type-scope abstraction.

## Reference source / commit / license

Repository at 8893a270; docs/.agent/reviews/binding-authoring-ergonomics.md.

## Completion criteria for the whole plan

All six improvements implemented, documented and demonstrated; full tests and example cgo/purego/ABI checks pass; committed clean tree.
