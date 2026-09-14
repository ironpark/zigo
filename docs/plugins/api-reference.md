# 플러그인 API 참조

현재 플러그인 계약은 `5.0`입니다. 이 문서는 `src/plugin.zig`이 제공하는 공개 타입과 실행
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
| `min_contract` | 현재 5.0 | 필요한 계약 version |
| `name` | 필수 | 식별 정보와 진단 접두사 |
| `Config` | `struct {}` | 빌드 전체 설정 타입 |
| `Facts` | `struct {}` | analyze 결과의 typed storage |
| `FunctionOptions` | `struct {}` | 함수 연결 옵션 |
| `TypeOptions` | `struct {}` | 타입 연결 옵션 |
| `ParamOptions` | `struct {}` | 매개변수 연결 옵션 |
| `ResultOptions` | `struct {}` | 결과 연결 옵션 |
| `FieldOptions` | `struct {}` | value·materialized 구조체 field 연결 옵션 |
| `TagOptions` | `struct {}` | 등록된 enum tag 연결 옵션 |
| `subjects` | 모든 node 종류 | 연결되는 node 종류 제한. 출력 언어가 아니라 node kind입니다 |
| `output_targets` | `&.{"go"}` | 렌더링할 수 있는 출력 언어. 해석된 target이 목록에 없으면 이 plugin은 아무것도 하지 않습니다 |
| `requires` | empty | 필수 플러그인 의존성 |
| `after` | empty | optional ordering constraint |
| `transform` | null | semantic document 교체·추가·제거 |
| `name_type` | null | 타입과 core reference rename |
| `map_type` | null | 기존 Go 어댑터 선택 |
| `name_function` | null | exact 공개 Go 함수 이름 |
| `validate` | null | core 이후 플러그인 진단 |
| `analyze` | null | lowering 뒤 typed fact 계산 |
| `visit` | null | 프로그램의 모든 node에서 불리는 하나뿐인 렌더링 hook |
| `claims` | null | 이 node의 공개 Go 표면을 이 플러그인이 가져감 |
| `source_files` | empty | framed 출력 언어 소스 file |
| `artifacts` | empty | exact 바이트 출력 |
| `imports` | empty | hook이 사용할 non-standard Go import |

semantic transform은 C ABI에 영향을 줄 수 있습니다. 렌더링 hook과 출력은 additive
Go surface만 만들며 shim, 헤더와 raw API를 바꾸지 않습니다.

## 렌더링 hook: `visit`

렌더링 hook은 하나입니다. generator는 render pass마다 프로그램을 document 순서로 한 번
걸으면서 각 node를 `subjects`가 덮는 모든 플러그인에게 등록 순서대로 넘깁니다.

```zig
.visit = visit,   // fn (Context, Node, *Builder) anyerror!void

fn visit(context: api.Context, node: api.Node, b: *api.Builder) !void {
    switch (node) {
        .type => |declaration| try b.emit(&.{ ... }, .{ .blank_after = true }),
        else => {},
    }
}
```

호출 중에 builder가 받은 출력은 그 node의 삽입 지점에 flush됩니다.

| `Node` | payload | 출력이 놓이는 곳 | `subjects`에 필요한 값 |
|---|---|---|---|
| `.package_begin` | 없음 | 패키지별 플러그인 file(`zigo_plugins_gen.go`) 앞 | 제한 없음 |
| `.package_end` | 없음 | 같은 file 뒤 | 제한 없음 |
| `.file_begin` | `FileInfo` | 공개 file의 package/import frame 안, body 앞 | 제한 없음 |
| `.file_end` | `FileInfo` | 같은 frame 안, body 뒤 | 제한 없음 |
| `.type` | `semantic.TypeDecl` | 공개 타입 직후 | 선언의 kind (`.handle`, `.value`, …) |
| `.function` | `abi.AbiFn` | 공개 function/메서드 직후 | `.function` |
| `.param` | `{ function, index }` | 그 function의 출력 뒤 | `.param` |
| `.result` | `abi.AbiFn` | 그 function의 출력 뒤 | `.result` |
| `.field` | `{ declaration, index }` | 그 타입의 출력 뒤 | `.field` |
| `.enum_tag` | `{ declaration, index }` | 그 타입의 출력 뒤 | `.enum_tag` |

선언 안쪽 node(`.param`, `.result`, `.field`, `.enum_tag`)는 자신의 삽입 지점이 없습니다.
소유한 function이나 타입의 출력 뒤에 이어서 쓰이며, 순서는 function → 매개변수 → 결과,
타입 → 멤버입니다. file과 package 경계는 subject가 없으므로 이 target으로 렌더링하는
모든 플러그인이 봅니다.

`Node`의 도우미는 다음과 같습니다.

- `subject()` — 이 node를 받으려면 `subjects`에 있어야 하는 값. 경계 node는 `null`
- `attachment()` — 이 node의 `ext`를 읽는 옵션 타입
- `ext()` — 이 node가 지닌 `ext` 객체
- `site(context)` — 이 node를 가리키는 진단 `Site`

`visit`은 render pass마다 불립니다. 결정적이어야 하고 analysis 상태를 바꾸면 안 됩니다.

## 메서드 대체

`visit`은 더하기만 합니다. 생성된 checked 메서드 **대신** 자신의 것을 놓으려면
`claims`가 그 선언을 주장합니다.

```zig
.claims = claims,   // fn (Context, Node) anyerror!bool
```

주장한 선언은 생성된 본문을 그대로 받되 exported 되지 않는 이름으로 받습니다.
`function` node의 visit은 `Method.checked_name`으로 그 이름을, `Method.public_name`으로
비어 있는 exported 이름을 읽어 자신의 래퍼를 씁니다. 결과는 Go 메서드 하나입니다.

- C 심볼, shim, 헤더, raw 패키지는 움직이지 않습니다. 바뀌는 것은 공개 Go 표면뿐입니다.
- 한 선언을 두 플러그인이 주장하면 `ZIGO024`로 거절됩니다.
- 공개 Go 표면을 가진 node는 `function`뿐입니다. 다른 node에 `true`를 답하면 `ZIGO065`로
  거절됩니다.
- exported 이름의 시그니처는 이제 플러그인의 것입니다. 그 선언이 `zigo.interface`나
  `implements`의 계약에 걸려 있다면 그 계약을 맞추는 것도 플러그인의 몫입니다.

## context

선언 옵션은 모든 context에서 한 가지 방법으로 읽습니다.

```zig
const options = try context.optionsOf(plugin, .type, declaration.ext) orelse return;
const options = try context.optionsOf(plugin, .function, function.origin.ext) orelse return;
```

선언 안쪽의 node도 같은 방법으로 읽습니다. `ext`를 어느 node에서 가져왔는지가 두 번째
인자이고, 그것이 곧 어느 옵션 타입으로 읽을지를 정합니다. 세 번째 인자로 `Node`를 그대로
넘기면 그 node의 `ext`를 읽습니다.

```zig
const on_param = try context.optionsOf(plugin, .param, function.origin.params[index].ext);
const on_result = try context.optionsOf(plugin, .result, function.origin.result_ext);
const on_field = try context.optionsOf(plugin, .field, declaration.fields[index].ext);
const on_tag = try context.optionsOf(plugin, .enum_tag, declaration.fields[index].ext);
const on_node = try context.optionsOf(plugin, .param, node);
```

`P`는 comptime `Plugin` 값입니다. attachment와 옵션 타입의 대응은 다음과 같습니다.

| attachment | 옵션 타입 | `subjects`에 필요한 값 |
|---|---|---|
| `.function` | `FunctionOptions` | `.function` |
| `.type` | `TypeOptions` | 선언의 kind (`.handle`, `.value`, …) |
| `.param` | `ParamOptions` | `.param` |
| `.result` | `ResultOptions` | `.result` |
| `.field` | `FieldOptions` | `.field` |
| `.enum_tag` | `TagOptions` | `.enum_tag` |

field와 enum tag는 IR에서 같은 node입니다. 어느 옵션 타입으로 읽을지는 그것을 담은 선언의
kind가 정합니다.

선언이 그 플러그인을 붙이지 않았으면 `null`, 읽을 수 없는 값이면
`error.InvalidPluginOptions`입니다. `subjects`에 없는 node 종류에 붙은 옵션은 선언 시점에
컴파일 error이고, `semantic.json`에 직접 써 넣은 경우에는 `<NAME>001` 진단입니다. 빌드
설정은 `context.config(plugin)`으로 읽습니다.

`TransformContext`:

- `allocator`, 불변 입력 `document`, configurations, diagnostics, `target`
- `config`, `optionsOf`, `diagnose`
- `reorderParameters(function, new_order)`

`ValidateContext`:

- `allocator`, validated semantic `document`, configurations, diagnostics, `facts`(쓰기 가능), `target`
- `config`, `optionsOf`, `diagnose`

`AnalyzeContext`:

- 렌더링 `Context`인 `render`
- `facts`(쓰기 가능), diagnostics
- `config`, `optionsOf`, `diagnose`

렌더링 `Context`:

- lowered `program`, allocator, `options`(아래 `PluginOptions`), 읽기 전용 `facts`
- 메서드 안쪽 node(`function`, `param`, `result`)의 `method` 정보
- 공개 타입/시그니처/doc writer와 header·식별자·리터럴 도우미
- `config`, `optionsOf`
- `sourceFilePathAlloc`, `publicFilePathAlloc`

`ArtifactContext`는 allocator, full program, `options`와 config/path 도우미만 제공합니다.

## `PluginOptions`

context의 `options`는 플러그인이 볼 수 있는 실행 정보만 담은 view입니다. generator의 link flag,
라이브러리 경로, backend 같은 emitter 자체 옵션은 여기 없습니다.

| 필드 | 의미 |
|---|---|
| `target` | 이번 실행의 출력 언어 (`context.target()`과 같음) |
| `go_module`, `go_package`, `go_package_path` | 생성 Go 모듈과 공개 패키지 |
| `raw_package_path` | raw 패키지 디렉터리 |
| `active_package` | 지금 렌더링 중인 공개 패키지. `null`은 단일 패키지 |
| `configurations` | 빌드가 컴파일해 넣은 플러그인 설정. `config(plugin)`이 읽음 |
| `helpers` / `emitsHelper(name)` | gated helper가 이 패키지에서 참조되는지 |
| `file` | visit이 실행 중인 파일 |

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
중복 put과 잘못된 타입 read는 오류입니다. 접근 경로는 하나입니다: `ValidateContext.facts`와
`AnalyzeContext.facts`는 쓰고, 렌더링 `Context.facts`는 읽기만 합니다.

진단의 `site`는 `plugin.site`가 만듭니다. `functionSite(function)`/`functionSiteFor(function, path)`와
`typeSite(declaration)`/`typeSiteFor(declaration, name)`은 reflection이 기록한 Zig 소스 위치를
가리키고, 위치가 없으면 `semantic.json`의 해당 항목으로 떨어집니다. interface나 session처럼 소스
위치가 없는 선언은 `documentSite(name)`입니다.

선언 안쪽 node도 각각의 도우미가 있습니다.

| 도우미 | 가리키는 곳 |
|---|---|
| `paramSite(function, index)` | 소스 스캔이 기록한 매개변수 이름 token. 없으면 함수의 위치이되 이름은 매개변수의 것 |
| `resultSite(function)` | 결과에는 고유한 token이 없으므로 함수의 위치 |
| `fieldSite(declaration, allocator, index)` | 컨테이너의 위치에 `<Type>.<field>` 이름 |
| `tagSite(declaration, allocator, index)` | `fieldSite`와 같되 tag가 읽히는 이름 |

## Go builder

hook은 Go 소스를 문자열로 쓰지 않고 `plugin.Builder`로 node를 조립한 뒤 렌더링합니다. node는
context allocator(run arena)에 복사되므로 loop 안에서 만들어도 렌더링까지 살아 있습니다.
`visit`은 builder를 인자로 받고, `source_files`와 `artifacts`는 `context.builder()`로
자신의 것을 만듭니다.

```zig
try b.emit(&.{try b.func(.{
    .doc = .{ .text = "IsKnown reports whether value is an exported tag." },
    .receiver = .{ .name = "value", .type = declaration.name },
    .name = "IsKnown",
    .signature = .{ .explicit = .{ .results = &.{b.ident("bool")} } },
    .body = &.{try b.ret(&.{b.boolean(false)})},
})}, .{ .blank_after = true });
```

### 렌더링

- `emit(decls, layout)` — `visit`의 출력에 씁니다. generator가 그 node의 삽입 지점에
  flush합니다
- `output()` — node가 철자하지 않는 text를 직접 써야 할 때의 출력 writer
- `render(writer, decls, layout)` — 선언 묶음을 `layout`(`blank_before`, `blank_after`,
  `blank_between`) 간격으로 씁니다
- `renderDecl(writer, decl)` — 선언 하나를 doc comment와 함께 씁니다
- `resultCount(function, .{ .omit_error })` — 공개 signature가 쓰는 결과 개수

### 선언

- `func(.{ .doc, .receiver, .name, .signature, .body, .single_line })`
- `variable(...)`, `constant(...)` — `var`/`const`
- `typeDecl(.{ .name, .alias, .spec })`, `structDecl(.{ .fields, .align_fields })`,
  `interfaceDecl(.{ .methods, .embeds })`
- `assertImplements(.{ .interface, .type_name, .form })` — `var _ I = (*T)(nil)` 또는 `*new(T)`
- `.{ .comment = .{ .text = ... } }`, `.{ .raw = ... }`

`doc`은 `.none`, `.text`(마커 없는 본문), `.rendered`(이미 `//`가 붙은 줄)입니다.

### statement

`ret`, `assign`, `define`, `declare`, `incDec`, `exprStmt`, `deferStmt`, `ifStmt`,
`switchStmt`, `forRange`, `forLoop`, `forever`, `block`, `.continue_stmt`, `.break_stmt`,
`.blank`, `commentStmt`, `rawStmt`.

### expression

`ident`, `string`, `int`, `boolean`, `.nil`, `sel`/`selName`, `indexExpr`, `call`/`callName`/
`callSel`/`callSpread`/`callForwarding`, `unary`/`addr`/`deref`/`not`, `bin`, `paren`, `ptr`,
`sliceOf`, `variadic`, `convert`, `funcType`, `funcLiteral`, `composite`/`compositeLines`,
그리고 escape hatch인 `raw`.

### generator가 답하는 node

core와 같은 Go spelling은 다음 node와 signature로 가져옵니다.

- `typeName(name)` — 패키지 qualifier까지 포함한 타입 이름
- `goType(node)` — semantic 타입 node의 Go 표기
- `valueType(function)` — 함수가 돌려주는 값의 Go 타입
- `Signature.function = .{ .function, .options }` — 공개 매개변수 목록과 결과
- `callForwarding(callee, function)` — 공개 매개변수 순서대로의 호출 인자

context에는 같은 정보를 직접 쓰는 writer도 남아 있습니다: `writeTypeName`, `writeGoType`,
`receiverNameAlloc`, `writeSignature`/`writeSignatureWith`, `writeParameters`,
`writeResultType`, `writeCallArguments`, `writeValueType`, `writeDoc`, `functionInfo`,
`identifierAlloc(allocator, name, .pascal | .camel)`.

직접 타입, 패키지 qualifier, 매개변수 이름이나 식별자를 재구성하면 하위 패키지와 이름 collision,
initialism 표기에서 core 출력과 달라질 수 있습니다.

## `SourceFile`

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
유지되므로 일반 소스 file에는 `SourceFile`을 사용하세요.

모든 출력 경로는 출력 root 안의 정규화된 상대 경로여야 하며 서로 충돌할 수 없습니다.
위반은 `ZIGO059`이며 기존 출력 tree를 변경하지 않습니다.
