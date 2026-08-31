# SCOPE

Modify validation, ABI IR/lowering, emitters, ABI diff, the tagged-union example, and user/design docs. Preserve the public successful-access API where possible; lifecycle misuse may gain explicit checked behavior.

# CONTEXT

## Current implementation and bottlenecks

Accessors are synthesized directly in emitters rather than lowering, skip `runtime.KeepAlive`, accept arbitrary scalar widths, export outside the panic wrapper path, and are visible to ABI diff only as an undifferentiated type change.

## Target structure and invariants

Lowering owns projection names, roles, payload ABI, and status semantics. Emitters consume that model. Status values distinguish mismatch, success, invalid handle, and panic; out parameters are untouched unless successful. Go wrappers keep owners alive and never dereference closed handles through C. Existing discriminants and projections form an append-compatible contract.
