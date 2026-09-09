# Rust 타겟 확장 타당성 연구

기준 커밋: 8f7d9b6a. 이 문서는 **구현 전 조사 기록**이며, 공개 문서가 아닙니다.
코드는 변경하지 않고 현재 구조만 측정했습니다.

## 결론

구조적으로 가능합니다. 파이프라인이 이미 **C ABI shim을 피벗**으로 언어 중립
영역과 Go 전용 영역으로 갈라져 있습니다. `Zig → 의미 IR → C ABI shim + C 헤더`
까지가 Go를 전혀 몰라도 되는 영역이고, Rust 백엔드는 그 아래 emit만 새로
쓰면 됩니다.

다만 **Rust 이미터를 먼저 쓰는 것은 권장하지 않습니다.** IR과 플러그인 계약에
Go 개념이 박혀 있어서, 그 상태로 두 번째 타겟을 붙이면 Go 필드를 Rust가
재해석하는 구조가 됩니다. 타겟 네임스페이싱을 선행해야 합니다.

## 레이어별 재사용도

| 레이어 | LOC | Rust 재사용도 | 근거 |
|---|---|---|---|
| `src/reflect/` | 8,611 | 거의 100% | Zig comptime 스캔·coverage. 출력 언어 무관 |
| `src/gen/ir/` | 2,765 | ~95% | 아래 "Go 전용 IR 필드" 11곳 제외 |
| `src/gen/lower.zig` + `lower/` | 3,292 | 대부분 | go 언급 35/2,904줄, 대부분 주석 |
| `src/gen/validate/` | 6,381 | 대부분 | `names.zig`(31)·`packages.zig` 제외 |
| `src/gen/emit/shim.zig`·`header.zig`·`target_types.zig` | 1,943 | 100% | Zig shim과 C 헤더 생성 |
| `src/gen/emit/` 나머지 | ~11,000 | 0% | Go 소스 생성 전용 |
| `src/plugin.zig` + `src/gen/plugins/` | ~37,000B + 722줄 | 계약 재설계 필요 | `writeGoType`·`GoFile`·`GoPackage` |
| `src/gen/generator.zig`·`cli.zig` | 2,295 | 부분 | go 언급 218/1,513, 118/782 |

## Go 전용 IR 필드 (`src/gen/ir/semantic.zig`)

| 위치 | 필드 | 성격 |
|---|---|---|
| `Parameter` | `go_error` | 콜백이 Go `error`를 반환 |
| `Parameter` | `go_adapter` | 사용자 Go 타입 변환 |
| `SemanticFn` | `go_name` | 공개 Go 이름 override |
| `SemanticFn` | `go_owner` | Go에서 묶이는 수신 타입 |
| `SemanticFn` | `return_go_adapter` | 반환 스칼라의 Go 타입 변환 |
| `SemanticFn` | `iterator` | Go 1.23 `iter.Seq` 래퍼 |
| `SemanticFn` | `implements` | `io.Writer`/`Reader`/`WriterTo`/`ReaderFrom` |
| `TypeDecl` | `go_adapter` | value struct의 Go 타입 변환 |
| 타입 | `GoAdapter` | `from_raw`/`to_raw`/`import`/`type` |
| 타입 | `Implements` | Go 표준 인터페이스 열거 |
| 타입 | `Package` / `package` | Go sub-package 개념 |

`src/declare.zig`(작성 DSL)에도 `go: GoAdapter`, `go_error`, `implements`가
대응 필드로 있고, `src/normalize.zig`·`src/reflect/walk.zig`가 이를 IR로 옮깁니다.

### 직렬화 제약

`Semantic`은 std.json으로 **Zig 필드 이름 그대로** 직렬화됩니다
(`emit_null_optional_fields = false`). 따라서 필드 이름 변경은 곧 wire format
변경입니다. 저장소에 `semantic.json` 스냅샷이 **104개** 있고
`tests/generator_cases/`가 **74개**입니다.

완충 장치는 이미 있습니다:

- `Semantic.ir_version: u32 = 1` — 버전 레버
- `Extensions` — 플러그인별 JSON을 원문 그대로 보관하는 네임스페이스 백.
  타겟 네임스페이스가 따를 선례로 적합합니다.

## Rust가 오히려 유리한 지점

- **error union → `Result<T, E>`**: Go의 `(T, error)` 튜플 규약보다 자연스러움
- **opaque handle → `Drop`**: `Close()` 수동 호출 문제 소멸
- **tagged union → Rust enum**: `emit/public_types.zig`의 projection·snapshot·
  sealed variant 기교 상당수가 불필요
- **materialized (결과 트리 직렬화, `108-materialized-result-trees`)**: Go GC가
  Zig 포인터를 잡지 못해 도입한 장치. Rust에서는 라이프타임 슬라이스나
  `Drop` 래퍼로 훨씬 얇게 처리 가능
- **callback**: cgo handle 우회 없이 `extern "C" fn` + `catch_unwind`
- **`.purego` 백엔드 → `libloading`**: `src/dynamic_library.zig` 개념이 그대로 대응

## 걸림돌

1. **IR의 Go 필드** — 위 표. 타겟 네임스페이스로 분리해야 함
2. **`context.Context` 취소** — Rust에 직접 대응물 없음. IR 개념 자체가 Go 모양인
   유일한 부분. `&AtomicBool` 취소 토큰 등 별도 추상화 설계 필요.
   `docs/.agent/research/zig-cancellation.md` 참고
3. **플러그인 계약 v2** — `contract_version 2.0`이 Go 소스를 직접 쓰는 API
   (`Context.writeGoType`, `GoFile`, `GoPackage`, `map_type → GoAdapter`).
   타겟 파라미터화 또는 v3. breaking change
4. **툴링** — `go_walk.zig`(coverage용 Go 소스 파싱), `doctor.zig`,
   `tool_probe.zig`, gofmt→rustfmt, `build.zig`의 `go build`/`go test` 오케스트레이션
5. **네이밍 규칙** — `naming.zig`의 `isGoKeyword`, `goParamNamesAlloc`,
   `validateGoPackageName`, `isGoIdentifier`, `libraryPathEnvironmentAlloc`
6. **이름** — `zigo` 자체가 Go 전제. 다중 타겟이면 브랜딩이 걸림

## 권장 순서

1. IR의 Go 전용 필드를 타겟 네임스페이스 확장으로 분리 (기존 문서 호환 유지)
2. `Target` 인터페이스 추출 — 키워드/네이밍/타입 스펠링/파일 레이아웃/포매터
3. 플러그인 계약을 타겟 제네릭으로 (또는 v3)
4. 스칼라 + 슬라이스 + error union만 커버하는 최소 Rust 백엔드를
   `examples/00-quick-start` 미러로

1~3만으로도 Rust 없이 코드베이스가 개선됩니다. 4는 그 위에 얹는 증명입니다.

## 규모 감

| 항목 | 추정 |
|---|---|
| 1~3 리팩터링 | 3~5K LOC |
| 최소 Rust 백엔드 | 신규 4~6K LOC |
| 현행 Go 기능 전부 대응 | 10~15K LOC |
