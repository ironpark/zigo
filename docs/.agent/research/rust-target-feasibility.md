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
3. ~~**플러그인 계약 v2**~~ → **해소됨** (플랜 `187-plugin-contract-targets`).
   계약 3.0이 해석된 타겟을 나르고 `Plugin.output_targets`가 기본값
   `&.{"go"}`로 필터링합니다. 최소 Rust 백엔드는 여기에 손대지 않았습니다.
   남은 것은 `validate.zig:218`의 `setGoName` 하드코딩입니다 —
   아래 "seam이 삐걱거린 곳" 2번
4. **툴링** — 부분 해소. `rustfmt`는 `Target.formatter`로 들어갔고
   `addRustBindings`가 shim 아카이브와 헤더까지 처리합니다. 남은 것:
   `go_walk.zig`(coverage용 Go 소스 파싱)에 대응하는 Rust 소스 파싱이 없어
   `rust-coverage`는 Zig 선언만 셉니다 — 실은 그것이 coverage의 본래 질문이라
   문제가 아닙니다. `doctor.zig`와 `tool_probe.zig`는 Go 툴체인 전용으로
   남았고, Rust 예제는 `doctor` 단계가 없습니다. `cargo`는 의존성을 해석하며
   네트워크에 접근할 수 있어 `zig build` 단계로 삼지 않았습니다
5. ~~**네이밍 규칙** — `naming.zig`의 `isGoKeyword`, `goParamNamesAlloc`,
   `validateGoPackageName`, `isGoIdentifier`, `libraryPathEnvironmentAlloc`~~
   → **해소됨** (플랜 `186-target-interface`). `src/gen/targets.zig`의 `Target`
   뒤로 모였고 Go 구현은 `src/gen/targets/go.zig`입니다. 남은 것은
   `pascalAlloc`/`camelAlloc` 안의 Go initialism 표(`id`→`ID` 등)로, 두 번째
   타겟을 실제로 붙이는 시점에 파라미터화하는 것이 낫다고 판단해 남겼습니다
6. **이름** — `zigo` 자체가 Go 전제. 다중 타겟이면 브랜딩이 걸림

## 권장 순서

1. ~~IR의 Go 전용 필드를 타겟 네임스페이스 확장으로 분리 (기존 문서 호환 유지)~~
   — 완료 (플랜 `185-ir-target-namespacing`)
2. ~~`Target` 인터페이스 추출 — 키워드/네이밍/타입 스펠링/파일 레이아웃/포매터~~
   — 완료 (플랜 `186-target-interface`). 타겟 결정은 CLI(`src/main.zig`의
   `outputTarget()`)와 빌드 통합(`addGoBindings`) 두 곳에서만 일어나고,
   validate·report·abi_diff·generator는 넘겨받은 `Target`을 읽습니다.
   `src/gen/emit/**`는 Go 이미터 자체이므로 seam 뒤에 있습니다
3. 플러그인 계약을 타겟 제네릭으로 (또는 v3) ← 다음 차례. `ZIGO059`
   출력 경로 규칙과 `src/plugin/interfaces.zig`의 인터페이스 이름 검사가
   여기에 묶여 아직 `targets.default`를 씁니다
4. ~~스칼라 + 슬라이스 + error union만 커버하는 최소 Rust 백엔드를
   `examples/00-quick-start` 미러로~~ — 완료 (플랜 `188-minimal-rust-backend`)

1~3만으로도 Rust 없이 코드베이스가 개선됩니다. 4는 그 위에 얹는 증명이었고,
아래가 그 결과입니다.

## 규모 감 — 추정 대비 실측

| 항목 | 추정 | 실측 |
|---|---|---|
| 1~3 리팩터링 | 3~5K LOC | 플랜 185·186·187 참조 |
| 최소 Rust 백엔드 | 신규 4~6K LOC | **신규 1,393줄** (아래 내역) |
| 현행 Go 기능 전부 대응 | 10~15K LOC | 미측정 |

추정이 3~4배 컸습니다. 원인은 하나입니다: seam이 실제로 버텼기 때문에 재사용이
"대부분"이 아니라 "전부"였습니다. 추정은 emit 아래 계층을 일부라도 다시 쓸
가능성을 계산에 넣었는데, 그럴 필요가 없었습니다.

### 최소 Rust 백엔드 내역

| 파일 | 줄 | 하는 일 |
|---|---|---|
| `src/gen/targets/rust_words.zig` | 132 | 키워드·식별자·경로형 변환 함수 이름. `std`만 import |
| `src/gen/targets/rust.zig` | 304 | `Target` 값과 Rust 네이밍 규칙 |
| `src/gen/emit_rust/types.zig` | 222 | 타입 스펠링과 "지원하지 않는 모양" 판정 |
| `src/gen/emit_rust/raw.zig` | 366 | `extern "C"` 블록과 마셜링 래퍼 |
| `src/gen/emit_rust/public.zig` | 291 | 공개 API와 오류 타입 |
| `src/gen/emit_rust/emit.zig` | 78 | 이미터 표와 파일 경로 |
| `build.zig`의 `addRustBindings` | 207 | 빌드 통합 |
| 합계 | **1,600** | (`addRustBindings` 포함) |

재사용한 것: `src/reflect/**`(8,611줄) 전부, `src/gen/ir/**`(2,765줄) 전부,
`src/gen/lower.zig`와 `lower/`(3,292줄) 전부, `src/gen/validate/**`(6,381줄)
전부, `emit/shim.zig`·`header.zig`·`target_types.zig`(1,943줄) 전부,
`errors_lock`·`output_manifest`·`sync_check`·`abi_diff`, 그리고 build 통합의
reflection 절반. **한 줄도 고치지 않았습니다** — validate·reflect·abi_diff·
report·generator 어느 caller도 Rust 때문에 바뀌지 않았습니다.

### seam이 버틴 곳

- **C ABI shim·panic 소스·C 헤더·`errors.lock.json`**: 같은 문서에서 두 타겟이
  바이트 단위로 같은 파일을 냅니다. `src/gen/generator.zig`의 테스트가 이걸
  주장으로 두지 않고 검사로 만듭니다.
- **`Target` 인터페이스**: 플랜 186이 예고한 인터페이스 변경은 정확히 하나
  (`exportedNameAlloc` 분할)뿐이었고, 나머지 멤버는 표에 적힌 대로 답했습니다.
- **`ir_version`**: `rust` 네임스페이스는 optional 추가라 마이그레이션도
  버전 범프도 필요 없었습니다. 플랜 185가 `abi-check` 베이스라인으로 깨졌던
  실패 유형이 아예 발생하지 않습니다.
- **plugin 계약**: 플랜 187의 `output_targets` 기본값 `&.{"go"}` 덕분에 Rust용
  조치가 전혀 필요 없었습니다.

### seam이 삐걱거린 곳

1. **`emit.core_emitters`가 중립 3개와 Go 전용 4개를 한 배열에 섞고 있었습니다.**
   `neutral_emitters ++ go_emitters`로 나눴습니다. 순서를 유지해야 manifest가
   안 움직입니다. `src/gen/emit/**`에 대한 유일한 수정입니다.
2. **`src/gen/validate/validate.zig:218`이 `setGoName`을 하드코딩합니다.**
   plugin의 `name_function` 훅 결과를 Go 네임스페이스에만 씁니다. `Target`에는
   이름 override의 *getter*(`nameOverride`)만 있고 setter가 없습니다. 최소
   범위에서는 Rust plugin이 없어 도달하지 않지만, 두 번째 타겟용 plugin을
   만들려면 여기가 먼저 바뀌어야 합니다.
3. **`generator.zig`의 `appendEmitters`가 `.go` 리터럴로 후행 개행을
   정규화했습니다.** `options.target.isSource()`로 바꿨습니다. Go의 답이 같은
   접미사 검사이므로 동작은 동일합니다.
4. **manifest의 `kind: "go"`가 "출력 언어의 framed 소스"를 뜻합니다.** `.rs`
   파일도 이 태그를 답니다. wire format이라 이름을 못 바꿉니다.
   `sync_check.compare`는 manifest를 경로로 훑으므로 동작하지만, manifest가
   없을 때의 fallback walk는 여전히 `.go` 전용입니다.
5. **`report`는 타겟을 못 받습니다.** 렌더링하는 모든 줄이 Go import 경로나
   cgo 링크 줄이어서, 플래그를 받아 Go 모양 보고서를 내는 것보다 안 받는 쪽이
   낫다고 판단했습니다. `src/main.zig`의 `reportTarget()`이 그 사실을 이름으로
   표시합니다.
6. **`Target.publicFunctionNameAlloc`의 constructor 분기가 `New{s}`를
   하드코딩합니다.** Go 관용구입니다. 최소 범위에 constructor가 없어 도달하지
   않지만, handle을 지원하는 순간 타겟 규칙이 되어야 합니다.

### 다음 사람에게

우선순위 순:

1. **opaque handle → `Drop`.** 조사 문서가 예상한 가장 큰 이득이고, 위 6번을
   먼저 해결해야 합니다.
2. **borrowed slice 반환.** 현재는 `Vec<T>`/`String`으로 복사합니다. 라이프타임
   슬라이스나 `Drop` 래퍼가 더 얇습니다.
3. **tagged union → Rust enum.**
4. **Rust plugin.** 위 2번을 먼저 해결해야 합니다.
5. **취소.** 여전히 별도 설계가 필요합니다. 걸림돌 #2는 그대로 남아 있습니다.
