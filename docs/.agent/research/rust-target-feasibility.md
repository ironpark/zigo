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

### 핸들과 버퍼 (플랜 `190-rust-handles-and-buffers`)

위 "다음 사람에게" 1·2번이 완료됐습니다. 예상은 맞았습니다 — 이 둘이 Rust
타겟의 가장 큰 이득입니다.

| 항목 | 결과 |
|---|---|
| opaque handle | `Drop`으로 스스로 해제. `close`·`is_closed`·유효성 플래그 없음 |
| 수신자 가변성 | `*T` → `&mut self`, 값 수신자 → `&self`. Go는 표현 불가 |
| 상태 코드 | Zig 에러 집합이 없으면 값 반환 + 결함 시 panic. Go는 전부 `error` |
| borrowed view | 라이프타임 래퍼, `Drop` 없음. 소유자보다 오래 살면 컴파일 오류 |
| 호출자 소유 버퍼 | `OwnedSlice<T>`, 복사 0회. release 함수 비공개 |
| 신규 코드 | `emit_rust` 957 → 2,096줄, `handles.zig`·`buffers.zig` 신규 |

`Ownership`·`AbiOpaque.lifecycle`·`Buffer` 모두 이미 lowering이 채워둔 것을
읽기만 했습니다. **IR 필드를 하나도 추가하지 않았고 `ir_version`도 그대로**입니다.

#### 이 플랜이 닫은 창

- 창 6(`New{s}` 하드코딩) → `Target.constructorNameAlloc`으로 이동. Go는
  `New<Type>`, Rust는 `new`.

#### 이 플랜이 찾은 버그 (모두 플랜 188/189 시점부터 존재)

경험적 감사 — Go generator case 74개 문서를 전부 Rust 타겟에 넣고, 통과한
결과를 `rustc -D warnings`로 컴파일 — 로 찾았습니다. 이 감사는 이제 플랜의
상시 검증입니다.

1. **좁은 정수 파라미터 + 에러 집합 없음 → 컴파일되지 않는 크레이트.**
   상태 코드 통로와 선언된 에러 집합을 한 질문으로 취급한 결과.
2. **콜백 있는 바인딩 → 패닉.** cgo 규약에서 콜백은 ABI 파라미터가 아니라
   `userdata` 토큰만 넘어가므로 ABI 스칼라를 보던 검사가 못 봤습니다.
3. **등록된 enum → tag 정수로 조용히 강등.** 컴파일은 되고 호출자는 `0`이
   무엇인지 알 수 없습니다.
4. **네임스페이스·sub-package → 평면화.** 같은 이름의 두 함수가 충돌합니다.
5. **주입된 파라미터가 공개 시그니처에 `()`로 누출.**
6. **`Buffer.release_function`은 `AbiFn.origin`과 절대 같지 않습니다.** 전자는
   checked promotion **전** 테이블을, 후자는 후 테이블을 가리킵니다. 이 비교로
   쓰인 코드 둘은 각각 `unreachable`에 도달하고, 모든 release 함수를 조용히
   공개했습니다. `Buffer.release` 인덱스가 올바른 수단입니다.
7. `error{E}!bool` → `Result<u8, Error>`.

감사 결과: 74개 중 7개가 컴파일되는 크레이트를 만들고, 67개가 기능 이름을 대는
`ZIGO060`으로 거부되고, **패닉하는 것은 없습니다.**

#### 이 플랜이 남긴 창

- **수신자의 const가 IR에 없습니다.** Zig `*const T` 수신자는 C 헤더에서
  비-const `zg_context *`가 되므로 `receiver_by_value`만 남습니다. Rust는
  포인터 수신자 전부에 `&mut self`를 주는데, 과하게 제한적이지만 unsound하지는
  않습니다. IR에 기록하면 Rust가 더 정확한 답을 낼 수 있습니다.
- **`constructorForInit`이 `goOwner()`를 읽습니다.** fallback(`namespace`)은
  중립이고 `.constructs` override만 Go 네임스페이스에 있습니다. 중립 `owner` +
  타겟별 override로 쪼개는 것이 정리입니다.

### 등록된 enum (플랜 `191-rust-enum-mapping`)

등록된 스칼라 enum이 공개 Rust API에서 이름을 유지합니다. 자유 함수뿐 아니라
핸들 메서드의 파라미터·직접 반환·상태 통로 payload에도 같은 변환을 씁니다.

- **닫힌 enum**: ABI tag의 폭·부호를 따르는 `#[repr(u8)]`, `#[repr(i32)]` 등의
  Rust enum. `TryFrom<tag>`가 공개 멤버를 명시적으로 매칭하며 오류에는 원래
  정수를 돌려줍니다. `From<Enum>`은 tag 정수를 돌려줍니다.
- **열린 enum**: private 정수 필드를 가진 `#[repr(transparent)]` newtype.
  `Type::Member` 상수와 `TryFrom`/`From`을 제공합니다. 모든 원래 Zig tag 값을
  보존하지만, `u3`/`i3`처럼 ABI가 폭을 늘린 경우에는 원래 범위를 검사합니다.
  `Unknown` variant나 `#[non_exhaustive]`에 의존하지 않으므로 미등록 판별자 UB가
  없습니다. 상수의 PascalCase는 닫힌 enum과 호출법을 같게 하려는 의도적인
  `non_upper_case_globals` 예외입니다.
- **경계**: extern과 raw 반환은 끝까지 정수입니다. 성공 상태를 확인한 후
  `TryFrom`으로 변환하고, 닫힌 enum의 알 수 없거나 생략된 값은 계약 위반으로
  Rust panic을 냅니다. Zig 오류 집합에 새 오류를 끼워 넣지 않습니다.
  enum 정수 인자를 받는 raw 래퍼는 `unsafe fn`입니다. 공개 API가 이름 있는
  타입을 받아 Zig 유효성 전제조건을 충족합니다.
- **멤버·텍스트**: `program.liveFields`로 omit을 반영합니다. Rust의 빈 initialism
  표를 재사용해 `http_id` → `HttpId`, `utf8_url` → `Utf8Url`을 얻습니다.
  `text: true`일 때만 `Display`·`FromStr`이 생깁니다. 열린 enum의 이름 없는 값은
  `Type(number)`로 표시하지만 파싱은 공개 Zig 멤버 이름만 허용합니다. Go의
  숫자 파싱 계약을 그대로 복사하지 않았습니다.
- **방어**: 빈 닫힌 enum과 Rust 이름 변환 충돌은 함수가 없어도 `ZIGO060`으로
  진단합니다. 빈 열린 enum은 지원하며 text trait의 불필요한 단일-arm match는
  clippy 검증에서 찾아 제거했습니다.

실제 재사용: `AbiEnum`·`Program.liveFields`·`typeDecl`, 기존 tag lowering과
`Shape.has_status_code`/`declares_errors`, 공유 `writeBody`, Rust의
`pascalWithInitialismsAlloc(..., &.{})`, 조건부 emitter 표. IR 필드 추가도
`ir_version` 변경도 없으며 Go emitter·shim·header는 수정하지 않았습니다.
파일 규모를 다시 센 결과, 그대로 재사용한 reflect **8,620줄**, IR **3,049줄**,
lowering **3,292줄**, validate **6,416줄**, shim/header/target_types **1,887줄**입니다.
Rust 전용 새 `enums.zig`는 **213줄**(진단·단위 테스트 포함), 기존 Rust emitter
수정은 **+75/-24줄**, 전체 `emit_rust`는 **2,096 → 2,360줄**입니다.
테스트 빌드에 runtime 실행 연결 **22줄**을 추가했습니다.

감사: 같은 Go 입력 74개에 대해 **before `accepted=7 broken= crashed=` →
after `accepted=10 broken= crashed=`**. 추가 통과는 `enum_text`, `enum_lookup`,
`enum_lookup_purego`입니다. 나머지 64개는 진단으로 거부되며 생성기 패닉은 없습니다.
처음 이유가 enum이라는 통계는 그 문서의 나머지 모든 선언도 지원한다는 뜻이
아닙니다. 예를 들어 `open_enum`에는 extern struct와 enum slice가 함께 있습니다.

검증: 루트 **434/434 스텝·672/672 테스트**, 별도 Rust 경계 runtime **7/7 테스트**,
두 신규 골든의 `rustc --edition 2021 -D warnings`·rustfmt·clippy 통과.
전체 generator 문서는 브랜치 시작 시 83개, 두 케이스 추가 후 **85개**입니다
(Go 74 + Rust 11). 기존 Go 골든은 전부 무변경입니다. 계획과 달리 기존 Rust
handle raw 골든 3개에서 중복 빈 줄을 하나씩 제거했습니다. 새 handle+enum
골든의 rustfmt가 드러낸 기존 문제이며 코드 동작에는 변화가 없습니다.
Go 예제 13개의 전체 단계·Go 테스트와 Rust 예제의 전체 단계·fmt·clippy·테스트가
모두 통과했고, 예제 트리는 브랜치 기준점 대비 전체가 무변경입니다. Rust 예제의
실제 결과는 `9 passed; 0 failed`, 데모의 첫 줄은 `2 + 3 = 5`, 마지막 줄은
`live bytes after drop = 0`입니다. 전체 출력은 플랜 191의 페이즈 1 Outcome에
기록했습니다.

### 다음 사람에게

우선순위 순:

1. **등록된 스칼라 enum 매핑은 완료** (플랜 191). 남은 enum 범위는
   **enum 값 수신자**의 `impl` 배치·마셜링과 **enum slice/buffer/optional**입니다.
   이들은 계속 `ZIGO060`으로 거부됩니다. 특히 네이티브 정수 배열을 닫힌 Rust
   enum 배열로 그대로 cast하면 UB가 될 수 있으므로 원소별 검사와 소유권 설계가
   먼저입니다. 열린 enum 자체는 지원되며, 이 남은 범위와 혼동하지 마세요.
2. **Zig 네임스페이스 → Rust 모듈**, sub-package → 크레이트 또는 모듈. 버그 4.
   첫 걸림돌인 문서가 8개로 enum보다 많습니다.
3. **tagged union → Rust enum.** 조사 문서가 예상한 세 번째 이득.
4. **Rust plugin.** `validate.zig`가 이제 `target.setNameOverride`를 쓰므로
   (플랜 189) 남은 것은 `Context.writeGoType` 계열의 Rust 대응물입니다.
5. **dependent handle** (부모보다 먼저 닫혀야 하는 자식). 자식 래퍼에 라이프타임
   파라미터가 필요하고, borrowed view의 기계장치에 소유권을 더한 모양입니다.
6. **취소.** 여전히 별도 설계가 필요합니다. 걸림돌 #2는 그대로 남아 있습니다.
