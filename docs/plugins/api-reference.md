# Plugin API 참조

현재 plugin contract는 `2.0`입니다. 이 문서는 `src/plugin.zig`이 제공하는 public type과 실행
순서를 요약합니다. 정확한 function signature는 [source](../../src/plugin.zig)가 정본입니다.

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

`requires`는 plugin이 등록·활성화되어야 하는 dependency이고 먼저 실행됩니다. `after`는 존재할
때만 순서를 정합니다. cycle과 duplicate name은 compile error입니다.

## `Plugin`

| field | 기본값 | 역할 |
|---|---|---|
| `min_contract` | 현재 2.0 | 필요한 contract version |
| `name` | 필수 | identity와 diagnostic prefix |
| `Config` | `struct {}` | build 전체 configuration type |
| `Facts` | `struct {}` | analyze 결과의 typed storage |
| `FunctionOptions` | `struct {}` | function attachment option |
| `TypeOptions` | `struct {}` | type attachment option |
| `targets` | 모든 type | attachment 대상 제한 |
| `requires` | empty | 필수 plugin dependency |
| `after` | empty | optional ordering constraint |
| `transform` | null | semantic document 교체·추가·제거 |
| `name_type` | null | type과 core reference rename |
| `map_type` | null | 기존 Go adapter 선택 |
| `name_function` | null | exact public Go function name |
| `validate` | null | core 이후 plugin diagnostic |
| `analyze` | null | lowering 뒤 typed fact 계산 |
| `method_hook` | null | public function/method 직후 body |
| `type_hook` | null | public type 직후 body |
| `file_hook` | null | public file body begin/end |
| `package_hook` | null | package별 plugin file body |
| `go_files` | empty | framed Go file output |
| `artifacts` | empty | exact byte output |
| `imports` | empty | hook이 사용할 non-standard Go import |

semantic transform은 C ABI에 영향을 줄 수 있습니다. rendering hook과 output은 additive
Go surface만 만들며 shim, header와 raw API를 바꾸지 않습니다.

## context

`TransformContext`:

- `allocator`, immutable input `document`, configurations, diagnostics
- `config`, `optionsOf`, `diagnose`
- `reorderParameters(function, new_order)`

`ValidateContext`:

- `allocator`, validated semantic `document`, configurations, diagnostics, facts
- `config`, `optionsOf`, `diagnose`

`AnalyzeContext`:

- rendering `Context`
- typed `Facts`
- diagnostics

render `Context`:

- lowered `program`, generator `options`, allocator
- method hook의 `method` 정보
- public type/signature/doc writer
- `functionOptions`, `typeOptions`, `config`
- `goFilePathAlloc`, `publicFilePathAlloc`

`ArtifactContext`는 allocator, full program, options와 config/path helper만 제공합니다.

## naming과 type mapping

- `name_type`은 registered type과 core IR reference를 함께 바꿉니다.
- `map_type`은 declaration, parameter와 result `TypeUse`에서 existing `GoAdapter`를 선택합니다.
- `name_function`은 변환하지 않을 exact exported Go name을 반환합니다.
- native Zig path는 유지됩니다.
- C symbol은 function rename과 별개이며 core collision validation을 통과해야 합니다.

later plugin은 앞선 plugin의 결과를 봅니다. plugin-owned opaque extension JSON은 type rename으로
자동 수정되지 않습니다.

## validation과 facts

diagnostic은 `severity`, plugin-owned `code`, `message`, `site`와 `hint`를 가집니다. 여러 문제를
한 번에 append할 수 있습니다.

`Facts.put`과 `Facts.get`은 plugin identity와 `DeclarationId`를 key로 하는 typed storage입니다.
validation/analyze에서 계산한 결과를 render hook이 source text 재분석 없이 읽도록 사용합니다.
중복 put과 잘못된 type read는 오류입니다.

## render writer

다음 helper로 core와 같은 Go spelling을 사용합니다.

- `writeTypeName`
- `writeGoType`
- `receiverNameAlloc`
- `writeSignature`, `writeSignatureWith`
- `writeParameters`, `writeResultType`, `writeCallArguments`
- `writeValueType`
- `writeDoc`
- `functionInfo`

직접 type, package qualifier 또는 parameter name을 재구성하면 하위 package와 name collision에서
core output과 달라질 수 있습니다.

## `GoFile`

| field | 기본값 | 의미 |
|---|---|---|
| `enabled` | null | output 조건 |
| `scope` | `.package` | `.package` 또는 `.document` |
| `package` | `.public` | `.public`, `.external_test`, `.raw` |
| `kind` | `.source` | `.source`, `.test_file` |
| `build_constraint` | null | single-line Go build expression |
| `imports` | null | candidate import 목록 |
| `pathAlloc` | 필수 | module-relative path |
| `render` | 필수 | framed Go body |

raw output은 document scope, external test output은 test kind여야 합니다. import는 실제 body가
qualifier를 사용할 때만 포함됩니다. source는 `gofmt`를 통과합니다.

## `Artifact`

artifact는 package/import framing이나 `gofmt` 없이 정확한 byte를 씁니다.

| field | 기본값 |
|---|---|
| `enabled` | null |
| `scope` | `.document` |
| `pathAlloc` | 필수 |
| `render` | 필수 |

Go가 아닌 schema, Markdown 또는 binary output에 사용합니다. `.go` artifact도 byte 그대로
유지되므로 일반 Go source에는 `GoFile`을 사용하세요.

모든 output path는 output root 안의 정규화된 상대 경로여야 하며 서로 충돌할 수 없습니다.
위반은 `ZIGO059`이며 기존 output tree를 변경하지 않습니다.
