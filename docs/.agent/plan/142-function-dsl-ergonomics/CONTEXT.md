# SCOPE

Update the public declaration and DSL modules, function-selection documentation, changelog, and tests.

# CONTEXT

## Current implementation and bottlenecks

`func(path).with(options)` repeats the full returns record for common ownership cases. `funcs` requires a root base and its fixed-size array cannot be mixed directly with individual entries in one slice literal.

## Target structure and invariants

All helpers return `zigo.Function` or fixed-size arrays of it. `collect` accepts only a tuple of functions and function arrays, preserves left-to-right order, and fails on unsupported values. Selection exclusions name declarations exactly. Every result still contains an exact `.path`.
