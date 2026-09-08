# SCOPE

Replace files with go_files and artifacts. Define document/package scope, build constraints and import ownership. Preserve atomic preparation and output collision checks. Migrate all consumers, document the contract and exercise actual generated Go packages.

# CONTEXT

File currently always receives public Go framing and participates in every package and helper pass. Exact artifacts need a separate path that preserves empty files and bytes. Standalone and test Go files must not run production file hooks or retain public helpers.
