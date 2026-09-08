# SCOPE

src/reflect/names.zig, docs/configuration.md, CHANGELOG.md, examples/05-pipeline/zigo/semantic.json.

# CONTEXT

## Current implementation and bottlenecks

root `fn_decl`은 visited였지만 안쪽 `fn_proto` 노드가 아니어서 0.18은 익명 fallback이 root 선언을 우연히 주웠고, 0.19는 그 fallback을 잠갔다.

## Target structure and invariants

prototype 위치를 named/root/file/anonymous scope로 구분한다. file scope는 receiver 타입 또는 반증 없음이 근거이고, anonymous는 generic 인스턴스만 받는다.
