# 플러그인 API 참조

현재 플러그인 계약은 `2.0`입니다. 이 문서는 `src/plugin.zig`이 제공하는 공개 타입과 실행
순서를 요약합니다. 정확한 함수 시그니처는 [소스](../../src/plugin.zig)가 정본입니다.

## 실행 순서

```text
configuration and dependency checks
  → transform (all plugins)
  → name_type (all plugins)
  → map_type and name_function (plugin order)
  → core validation
  → plugin validation
  → core feature expansion and lowering
  → analyze
  → rendering hooks and outputs
```

`requires`는 플러그인이 등록·활성화되어야 하는 의존성이고 먼저 실행됩니다. `after`는 존재할
때만 순서를 정합니다. cycle과 duplicate 이름은 컴파일 error입니다.

## `Plugin`

| 필드 | 기본값 | 역할 |
|---|---|---|
| `min_contract` | 현재 2.0 | 필요한 계약 version |
| `name` | 필수 | 식별 정보와 진단 접두사 |
| `Config` | `struct {}` | 빌드 전체 설정 타입 |
| `Facts` | `struct {}` | analyze 결과의 typed storage |
| `FunctionOptions` | `struct {}` | 함수 연결 옵션 |
| `TypeOptions` | `struct {}` | 타입 연결 옵션 |
| `subjects` | 함수와 모든 지원 타입 | 연결되는 선언 종류 제한. 출력 언어가 아니라 declaration kind입니다 |
| `requires` | empty | 필수 플러그인 의존성 |
| `after` | empty | optional ordering constraint |
| `transform` | null | semantic document 교체·추가·제거 |
| `name_type` | null | 타입과 core reference rename |
| `map_type` | null | 기존 Go 어댑터 선택 |
| `name_function` | null | exact 공개 Go 함수 이름 |
| `validate` | null | core 이후 플러그인 진단 |
| `analyze` | null | lowering 뒤 typed fact 계산 |
| `method_hook` | null | 공개 function/메서드 직후 body |
| `type_hook` | null | 공개 타입 직후 body |
| `file_hook` | null | 공개 file body begin/end |
| `package_hook` | null | 패키지별 플러그인 file body |
| `go_files` | empty | framed Go file 출력 |
| `artifacts` | empty | exact 바이트 출력 |
| `imports` | empty | hook이 사용할 non-standard Go import |

semantic transform은 C ABI에 영향을 줄 수 있습니다. 렌더링 hook과 출력은 additive
Go surface만 만들며 shim, 헤더와 raw API를 바꾸지 않습니다.

## context

`TransformContext`:

- `allocator`, 불변 입력 `document`, configurations, diagnostics
- `config`, `optionsOf`, `diagnose`
- `reorderParameters(function, new_order)`

`ValidateContext`:

- `allocator`, validated semantic `document`, configurations, diagnostics, facts
- `config`, `optionsOf`, `diagnose`

`AnalyzeContext`:

- 렌더링 `Context`
- typed `Facts`
- diagnostics

렌더링 `Context`:

- lowered `program`, generator `options`, allocator
- 메서드 hook의 `method` 정보
- 공개 타입/시그니처/doc writer
- `functionOptions`, `typeOptions`, `config`
- `goFilePathAlloc`, `publicFilePathAlloc`

`ArtifactContext`는 allocator, full program, options와 config/path 도우미만 제공합니다.

## naming과 타입 mapping

- `name_type`은 registered 타입과 core IR reference를 함께 바꿉니다.
- `map_type`은 선언, 매개변수와 결과 `TypeUse`에서 existing `GoAdapter`를 선택합니다.
- `name_function`은 변환하지 않을 exact exported Go 이름을 반환합니다.
- 네이티브 Zig 경로는 유지됩니다.
- C 심볼은 함수 rename과 별개이며 core collision 검증을 통과해야 합니다.

later 플러그인은 앞선 플러그인의 결과를 봅니다. 플러그인-owned opaque extension JSON은 타입 rename으로
자동 수정되지 않습니다.

## 검증과 facts

진단은 `severity`, 플러그인-owned `code`, `message`, `site`와 `hint`를 가집니다. 여러 문제를
한 번에 append할 수 있습니다.

`Facts.put`과 `Facts.get`은 플러그인 식별 정보와 `DeclarationId`를 key로 하는 typed storage입니다.
validation/analyze에서 계산한 결과를 렌더링 hook이 소스 text 재분석 없이 읽도록 사용합니다.
중복 put과 잘못된 타입 read는 오류입니다.

## 렌더링 writer

다음 도우미로 core와 같은 Go spelling을 사용합니다.

- `writeTypeName`
- `writeGoType`
- `receiverNameAlloc`
- `writeSignature`, `writeSignatureWith`
- `writeParameters`, `writeResultType`, `writeCallArguments`
- `writeValueType`
- `writeDoc`
- `functionInfo`

직접 타입, 패키지 qualifier 또는 매개변수 이름을 재구성하면 하위 패키지와 이름 collision에서
core 출력과 달라질 수 있습니다.

## `GoFile`

| 필드 | 기본값 | 의미 |
|---|---|---|
| `enabled` | null | 출력 조건 |
| `scope` | `.package` | `.package` 또는 `.document` |
| `package` | `.public` | `.public`, `.external_test`, `.raw` |
| `kind` | `.source` | `.source`, `.test_file` |
| `build_constraint` | null | single-line Go 빌드 expression |
| `imports` | null | candidate import 목록 |
| `pathAlloc` | 필수 | module-relative 경로 |
| `render` | 필수 | framed Go body |

raw 출력은 document scope, external 테스트 출력은 테스트 kind여야 합니다. import는 실제 body가
qualifier를 사용할 때만 포함됩니다. 소스는 `gofmt`를 통과합니다.

## `Artifact`

산출물은 패키지/import framing이나 `gofmt` 없이 정확한 바이트를 씁니다.

| 필드 | 기본값 |
|---|---|
| `enabled` | null |
| `scope` | `.document` |
| `pathAlloc` | 필수 |
| `render` | 필수 |

Go가 아닌 schema, Markdown 또는 binary 출력에 사용합니다. `.go` 산출물도 바이트 그대로
유지되므로 일반 Go 소스에는 `GoFile`을 사용하세요.

모든 출력 경로는 출력 root 안의 정규화된 상대 경로여야 하며 서로 충돌할 수 없습니다.
위반은 `ZIGO059`이며 기존 출력 tree를 변경하지 않습니다.
