# GOALS

## Problem and the end result from the user's point of view

The internal generator protocol should remain a build implementation detail without relying on argument counts and fragile positional indexes.

## Measurable goals

- Introduce `generate`, `check`, and `abi-diff` subcommands with named arguments.
- Remove legacy positional parsing and cover defaults, required values, duplicates, and invalid flags with unit tests.
- Preserve every generated artifact and build behavior.

## Supported scope and non-goals

This changes only the internal build-to-generator protocol. It does not turn `zigo-gen` into a supported user-facing CLI or change generated source APIs.

## Reference source / commit / license

The work is based on the current repository; no external code is copied.

## Completion criteria for the whole plan

Parser tests and root tests pass, every example generates/checks/tests successfully, and no positional generator invocation remains.
