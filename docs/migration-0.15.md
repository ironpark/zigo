# 0.15 바인딩 선언 마이그레이션

이 문서는 0.14 → 0.15 변환의 기록입니다. 현재 API까지 옮기려면 이 변환 이후
[작성 API 마이그레이션](migration-authoring.md)을 적용하세요. 아래 스크립트는 0.15 형식까지만 만듭니다.

0.15부터 `zigo.define`은 익명 구조체를 추측해 읽지 않고 `zigo.Binding`을 받습니다. 이전 선언은
호환되지 않으며 `bindings.zig`를 한 번에 새 스키마로 옮겨야 합니다. 생성되는 C ABI,
`semantic.json`, Go API는 선언 순서 변경(`functions` 뒤에 `methods`)이나 새 `doc` override를
사용하지 않는 한 그대로입니다.

## 핵심 대응표

| 0.14 | 0.15 |
|---|---|
| `.types = .{ ... }` | `.types = &.{ ... }` |
| `.{ .type = T, .repr = .@"opaque" }` | `.{ .handle = .{ .type = T } }` |
| `.{ .type = T, .repr = .value }` | `.{ .value = .{ .type = T } }` |
| `.{ .type = T, .repr = .materialized }` | `.{ .materialized = .{ .type = T } }` |
| `.{ .type = T, .repr = .enumeration }` | `.{ .enumeration = .{ .type = T } }` |
| `.{ .type = T, .repr = .tagged_union }` | `.{ .tagged_union = .{ .type = T } }` |
| `.{ .type = T, .repr = .callback, .name = "Fn" }` | `.{ .callback = .{ .type = T, .name = "Fn" } }` |
| `.field_meta = .{ .x = .{ .semantic = H } }` | `.fields = &.{.{ .name = "x", .semantic = H }}` |
| `.omit_variants = .{"x"}` | `.omit = &.{"x"}` |
| `.params = .{"x"}, .param_meta = .{ .x = C }` | `.params = &.{.{ .name = "x", ...C }}` |
| `.written = .@"return"` | `.written = .result` |
| `.returns = .caller, .semantic = H, .release = P, .go = G` | `.returns = .{ .ownership = .caller, .semantic = H, .release = P, .go = G }` |
| `.receiver = "Handle"` | `.receiver = library.Handle` |
| `.constructs = "Handle"`, `.destroys = "Handle"` | `.constructs = library.Handle`, `.destroys = library.Handle` |
| 함수 목록 안의 receiver group | 최상위 `.methods = &.{ ... }` |
| `.allocator = "gpa"`, `.io = "io"` | `.allocator = .{ .path = "gpa" }`, `.io = .{ .path = "io" }` |

`types`, `functions`, `methods`, `packages`, `interfaces`와 그 안의 목록은 모두 slice이므로 `&.{}`를
사용합니다. `params`도 이름 목록이 아니라 위치별 `zigo.Param` 목록입니다. 이름을 생략한
`.{}`는 소스에서 이름을 보강하고, 찾지 못하면 `p0`, `p1`처럼 생성합니다.

## 예시

```zig
pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .{ .path = "gpa" },
    .types = &.{
        .{ .handle = .{ .type = library.Context, .doc = "Context owns native state." } },
        .{ .enumeration = .{ .type = library.Mode, .text = true } },
    },
    .functions = &.{
        .{
            .path = "root.openContext",
            .constructs = library.Context,
            .params = &.{.{ .name = "name", .semantic = .utf8_string }},
        },
        .{
            .path = "Context.take",
            .returns = .{ .ownership = .caller, .release = "Context.free" },
        },
    },
    .methods = &.{.{
        .receiver = library.Mode,
        .strip_prefix = "mode",
        .functions = &.{.{ .path = "root.modeLabel" }},
    }},
});
```

모르는 키, variant에 맞지 않는 키, 문자열로 남긴 타입 참조는 이제 Zig 컴파일러가 선언 위치에서
바로 거부합니다. 예전 `ZIGO057` 검사는 필요하지 않습니다. 파라미터 이름과 계약이 같은
`Param`에 함께 있어 고아 metadata를 만들 수 없기 때문입니다.

## 확인 순서

1. `zig fmt src/bindings.zig`
2. `zig build test --summary all`
3. `zig build go` (purego 출력이 있으면 `zig build purego-go`도 실행)
4. 생성물을 커밋한 뒤 `zig build go-check --summary all`

저장소 전체를 기계적으로 옮길 때는 `python3 scripts/migrate-bindings.py <bindings.zig>...`를
사용할 수 있습니다. 변환 후에는 반드시 diff를 검토하고 위 검사를 실행하세요.
