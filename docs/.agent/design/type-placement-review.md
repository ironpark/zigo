# Zig 타입 배치 점검

점검 기준 소스는 패키지 배포 목록(`build.zig.zon`)에 포함된 `build.zig`와 `src/`다. 예제, 테스트, 문서는 기존 경로의 소비 증거로만 조사했다. 이 문서는 배치 평가이며 소스 이동 결정이나 구현 변경이 아니다.

## 결론

- canonical entry 76개를 확인했다: 파일 루트 17개, 이름 있는 타입 46개, 로컬/익명 타입 13개.
- `Conforms` 54개, `Improvement candidate` 22개, `Intentional retention` 0개다.
- 22개 후보는 모두 **같은 파일 안에서 의미상 소유 타입 아래로 중첩할 후보**다. 현재 프로젝트에는 타입별 파일 분리 정책이나 물리 라인 제한이 없으므로 파일 이동 후보는 없다.
- 가장 큰 파일은 `src/gen/emit.zig` 1,069줄이지만, 규칙상 설정된 제한이 없으면 크기 조건은 false다. 크기만으로 분리 후보로 판정하지 않았다.
- 생산 코드에는 타입 alias나 type factory가 없다. 테스트 코드의 계산식 alias 두 개는 AST상 `unresolved`였고 소스 문맥으로 확인했다.

## 조사 데이터와 경계

Zig 0.16.0에서 `ziglyzer` 소스 `150cfba`를 `make install`로 설치했고, `/Users/ironpark/.local/bin/ziglyzer`가 `PATH`에서 선택되는 것을 확인했다. 대상 소스 기준은 `ca3f2a4`다. 원시 생산 타입 목록은 [`reports/type-placement/types.txt`](../../../reports/type-placement/types.txt)에 보존했다.

실행한 핵심 명령은 다음과 같다.

```sh
ziglyzer --types src
ziglyzer --types .
ziglyzer --report src /tmp/zigo-type-placement-review/unrooted
ziglyzer --report src /tmp/zigo-type-placement-review/root \
  --root-file root.zig --root-name zigo
ziglyzer --report src /tmp/zigo-type-placement-review/main \
  --root-file main.zig --root-name zigo-cli
ziglyzer --report . /tmp/zigo-type-placement-review/build \
  --root-file build.zig --root-name zigo-build
```

`src/` 최상위에 `root.zig`와 `main.zig`가 모두 있어 자동 public root는 선택되지 않았다. 따라서 `build.zig`, `root.zig`, `main.zig`, `reflect/main.zig`와 빌드에서 독립 모듈로 등록되는 `semantic`, `abi`, `errors_lock`, `diagnostic`, `sync_check`, `abi_diff`, `reflect_walk`, `reflect_names`를 각각 명시 root로 다시 조사했다. 경로 import로 쓰이는 `generator`, `emit`, `lower`, `naming`, `validate`도 각각 명시 root로 확인했다.

아래의 `zigo-build`는 두 `zigo` root를 보고서에서 구분하려고 준 조사용 이름이다. 실제 소비자 build script의 관례적 경로는 `zigo.Options`처럼 소비자가 dependency에 붙인 이름을 따른다. `semantic.*`, `abi.*` 같은 경로는 빌드 그래프 내부 모듈 API이며 패키지 사용자 API가 아니다. 아키텍처 문서도 reflector와 generator를 사용자에게 비공개로 규정한다.

## 공통 물리 배치 판정

검색 결과 타입별 파일 분리 정책과 설정된 라인 제한은 없었다. `04-implementation-plan.md`의 예시 트리는 기능 단위 구조 제안이지 owner별 타입 파일 분리 정책이 아니다. 따라서 모든 named type의 현재/예상 물리 위치는 owner 구현 파일로 동일하고, split-file form은 적용 대상이 아니다. 파일별 실제 물리 줄 수는 다음과 같다.

| 파일 | 줄 | 파일 | 줄 |
|---|---:|---|---:|
| `build.zig` | 376 | `src/gen/emit.zig` | 1,069 |
| `src/gen/abi_diff.zig` | 224 | `src/gen/generator.zig` | 310 |
| `src/gen/diagnostic.zig` | 43 | `src/gen/validate.zig` | 298 |
| `src/gen/ir/semantic.zig` | 269 | `src/reflect/walk.zig` | 435 |
| `src/gen/ir/abi.zig` | 61 | `src/reflect/names.zig` | 159 |
| `src/gen/ir/errors_lock.zig` | 128 | `src/reflect/main.zig` | 35 |
| `src/gen/lower.zig` | 162 | `src/gen/naming.zig` | 65 |
| `src/gen/sync_check.zig` | 72 | `src/main.zig` | 84 |
| `src/root.zig` | 16 |  |  |

## Improvement candidates

다음 표는 요청된 assessment record의 모든 필드를 타입별로 기록한다. `고정`은 fixed type body, `공개`는 해당 모듈 root에서 `pub`인 경로를 뜻한다. 모든 후보는 현재 파일을 유지하며 canonical body만 예상 owner 아래로 중첩하는 형태다.

| Type | Canonical implementation location | Confirmed public paths | Current owner / expected owner | Current declaration form / expected declaration form | Current visibility / expected visibility | Current physical location / expected physical location | Current file form / expected file form | Rationale | Compatibility constraints | Final assessment |
|---|---|---|---|---|---|---|---|---|---|---|
| `CgoFlags` | `build.zig:3:22` | `zigo-build.CgoFlags` | build feature / `Options` | 고정 struct / 고정 struct | 공개 / 공개 | `build.zig` / 동일 | 적용 안 함 / 적용 안 함 | `cflags`와 `ldflags`는 `addGoBindings`의 `Options.cgo_flags`에서만 의미가 생긴다. | 사용자-facing 기존 경로다. 변경 시 canonical은 `Options.CgoFlags`, 기존 경로는 `pub const CgoFlags = Options.CgoFlags` compatibility alias로 유지해야 한다. | **Improvement candidate** |
| `LinkMode` | `build.zig:8:22` | `zigo-build.LinkMode` | build feature / `Options` | 고정 enum / 고정 enum | 공개 / 공개 | `build.zig` / 동일 | 적용 안 함 / 적용 안 함 | 값은 `Options.link_mode`의 선택지만 표현한다. | 사용자-facing 기존 경로다. `Options.LinkMode`로 옮길 경우 기존 경로를 compatibility alias로 유지해야 한다. | **Improvement candidate** |
| `ChangeKind` | `src/gen/abi_diff.zig:4:24` | `abi_diff.ChangeKind` | `abi_diff` / `Change` | 고정 enum / 고정 enum | 공개 / 공개 | `src/gen/abi_diff.zig` / 동일 | 적용 안 함 / 적용 안 함 | 각 값은 오직 `Change.kind`의 분류이며 `Report` 자체의 상태가 아니다. | 내부 모듈 경로다. `Change.Kind`로 갱신하고 필요하면 이전 경로를 compatibility alias로 둘 수 있다. | **Improvement candidate** |
| `Severity` | `src/gen/diagnostic.zig:3:22` | `diagnostic.Severity` | `diagnostic` / `Diagnostic` | 고정 enum / 고정 enum | 공개 / 공개 | `src/gen/diagnostic.zig` / 동일 | 적용 안 함 / 적용 안 함 | 현재 사용은 모두 `Diagnostic.severity`의 타입이다. | `validate.zig`와 진단 테스트를 함께 갱신한다. 외부 공개 package 경로는 아니다. | **Improvement candidate** |
| `Site` | `src/gen/diagnostic.zig:5:18` | `diagnostic.Site` | `diagnostic` / `Diagnostic` | 고정 struct / 고정 struct | 공개 / 공개 | `src/gen/diagnostic.zig` / 동일 | 적용 안 함 / 적용 안 함 | `path`와 `declaration` 쌍은 현재 `Diagnostic.site` 문맥에서만 쓰인다. | `validate.zig`와 테스트를 같은 change set에서 갱신한다. | **Improvement candidate** |
| `ErrorCode` | `src/gen/ir/errors_lock.zig:3:23` | `errors_lock.ErrorCode` | `errors_lock` / `ErrorsLock` | 고정 struct / 고정 struct | 공개 / 공개 | `src/gen/ir/errors_lock.zig` / 동일 | 적용 안 함 / 적용 안 함 | 이 구조체는 lock의 `codes` 항목이고 parse/serialize/sort가 모두 `ErrorsLock` 생명주기에 묶인다. ABI의 별도 `abi.ErrorCode`와도 구분해야 한다. | generator는 구체 경로를 거의 쓰지 않고 필드로 순회한다. 내부 사용자 보호가 필요하면 이전 경로 alias를 둔다. | **Improvement candidate** |
| `Int` | `src/gen/ir/semantic.zig:3:17` | `semantic.Int` | `semantic` / `TypeNode` | 고정 struct / 고정 struct | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | semantic integer 자체가 아니라 `TypeNode.int` payload다. | JSON 모양은 변하지 않는다. 내부 경로가 필요하면 `pub const Int = TypeNode.Int` alias로 이행할 수 있다. | **Improvement candidate** |
| `Float` | `src/gen/ir/semantic.zig:9:19` | `semantic.Float` | `semantic` / `TypeNode` | 고정 struct / 고정 struct | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | `TypeNode.float` payload로만 사용된다. | `TypeNode.Float` 전환; 필요 시 이전 경로 alias. | **Improvement candidate** |
| `Ref` | `src/gen/ir/semantic.zig:10:17` | `semantic.Ref` | `semantic` / `TypeNode` | 고정 struct / 고정 struct | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | `TypeNode.enum`과 `TypeNode.value_struct`가 공유하는 node-reference payload다. | 두 union field를 한 change set에서 갱신한다. 필요 시 이전 경로 alias. | **Improvement candidate** |
| `OpaquePtr` | `src/gen/ir/semantic.zig:11:23` | `semantic.OpaquePtr` | `semantic` / `TypeNode` | 고정 struct / 고정 struct | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | `TypeNode.opaque_ptr` payload로만 사용된다. | JSON 및 ABI 값은 불변; 필요 시 이전 경로 alias. | **Improvement candidate** |
| `Slice` | `src/gen/ir/semantic.zig:16:19` | `semantic.Slice` | `semantic` / `TypeNode` | 고정 struct / 고정 struct | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | `element: *TypeNode`로 parent에 직접 의존하는 `TypeNode.slice` payload다. | 같은 파일 내 재중첩이므로 import cycle은 없다. 필요 시 이전 경로 alias. | **Improvement candidate** |
| `Optional` | `src/gen/ir/semantic.zig:20:22` | `semantic.Optional` | `semantic` / `TypeNode` | 고정 struct / 고정 struct | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | `child: *TypeNode`로 parent에 직접 의존하는 optional payload다. | 같은 파일에서 갱신; 필요 시 이전 경로 alias. | **Improvement candidate** |
| `ErrorUnion` | `src/gen/ir/semantic.zig:21:24` | `semantic.ErrorUnion` | `semantic` / `TypeNode` | 고정 struct / 고정 struct | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | `payload: *TypeNode`를 가진 `TypeNode.error_union` 전용 payload다. | generator/validator는 union field를 통해 접근한다. 필요 시 이전 경로 alias. | **Improvement candidate** |
| `Callback` | `src/gen/ir/semantic.zig:26:22` | `semantic.Callback` | `semantic` / `TypeNode` | 고정 struct / 고정 struct | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | params/return이 `TypeNode`이고 `TypeNode.callback` payload다. | `emit.zig:792`의 명시 경로를 `semantic.TypeNode.Callback`로 갱신하거나 이전 경로 alias를 둔다. | **Improvement candidate** |
| `NameSource` | `src/gen/ir/semantic.zig:196:24` | `semantic.NameSource` | `semantic` / `Parameter` | 고정 enum / 고정 enum | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | AST/fallback/sidecar 값은 `Parameter.name_source`의 provenance만 표현한다. | 명시적 외부 경로 사용은 없지만 공개 field type이므로 `Parameter.NameSource`는 공개여야 한다. | **Improvement candidate** |
| `Direction` | `src/gen/ir/semantic.zig:197:23` | `semantic.Direction` | `semantic` / `Parameter` | 고정 enum / 고정 enum | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | in/inout/out 값은 `Parameter.direction`에만 의미가 있다. | `Parameter.Direction`를 공개하고 필요 시 이전 경로 alias. | **Improvement candidate** |
| `Retention` | `src/gen/ir/semantic.zig:198:23` | `semantic.Retention` | `semantic` / `Parameter` | 고정 enum / 고정 enum | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | borrowed/retained 값은 parameter callback 보존 정책만 표현한다. | ABI diff와 emit은 `Parameter` 값을 통해 접근한다. 필요 시 이전 경로 alias. | **Improvement candidate** |
| `Ownership` | `src/gen/ir/semantic.zig:200:23` | `semantic.Ownership` | `semantic` / `SemanticFn` | 고정 enum / 고정 enum | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | borrowed/caller/library 값은 `SemanticFn.ownership` 반환 소유권만 표현한다. | `SemanticFn.Ownership`를 공개하고 필요 시 이전 경로 alias. | **Improvement candidate** |
| `TypeKind` | `src/gen/ir/semantic.zig:224:22` | `semantic.TypeKind` | `semantic` / `TypeDecl` | 고정 enum / 고정 enum | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | 값은 `TypeDecl.kind`의 분류다. | `reflect/walk.zig:411`의 명시 경로를 갱신하거나 이전 경로 alias를 둔다. | **Improvement candidate** |
| `Layout` | `src/gen/ir/semantic.zig:225:20` | `semantic.Layout` | `semantic` / `TypeDecl` | 고정 enum / 고정 enum | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | extern/packed 값은 `TypeDecl.layout`에만 의미가 있다. | 공개 field type이므로 `TypeDecl.Layout`는 공개 유지; 필요 시 이전 경로 alias. | **Improvement candidate** |
| `TypeField` | `src/gen/ir/semantic.zig:226:23` | `semantic.TypeField` | `semantic` / `TypeDecl` | 고정 struct / 고정 struct | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | declaration의 fields 원소이며 독립 semantic node로 사용되지 않는다. | `reflect/walk.zig:192`를 `semantic.TypeDecl.Field`로 갱신하거나 이전 경로 alias를 둔다. | **Improvement candidate** |
| `DifferenceKind` | `src/gen/sync_check.zig:3:28` | `sync_check.DifferenceKind` | `sync_check` / `Difference` | 고정 enum / 고정 enum | 공개 / 공개 | `src/gen/sync_check.zig` / 동일 | 적용 안 함 / 적용 안 함 | missing/content 값은 `Difference.kind`의 분류다. | `Difference.Kind`로 갱신하고 내부 호환이 필요하면 이전 경로 alias. | **Improvement candidate** |

이 후보들은 다섯 change set으로 묶는 것이 안전하다.

1. `build.Options`: `CgoFlags`, `LinkMode`; 외부 compatibility alias 필수.
2. `semantic.TypeNode`: 8개 payload type; recursive pointer와 JSON round trip을 함께 검증.
3. `semantic.Parameter`와 `semantic.SemanticFn`: metadata enum 4개; reflector, validator, ABI diff 동시 검증.
4. `semantic.TypeDecl`: `TypeKind`, `Layout`, `TypeField`; reflection과 ABI diff 동시 검증.
5. 작은 내부 owner 정리: `ChangeKind`, `Severity`, `Site`, `errors_lock.ErrorCode`, `DifferenceKind`; 각 모듈 테스트로 독립 검증.

## Conforming named types

각 행은 별도 assessment record다. 물리 위치는 canonical location의 현재 파일과 동일하고, split-file form은 현재/예상 모두 적용 대상이 아니다.

| Type | Canonical implementation location | Confirmed public paths | Current owner / expected owner | Current declaration form / expected declaration form | Current visibility / expected visibility | Current physical location / expected physical location | Current file form / expected file form | Rationale | Compatibility constraints | Final assessment |
|---|---|---|---|---|---|---|---|---|---|---|
| `Options` (build) | `build.zig:10:21` | `zigo-build.Options` | build Go-binding feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `build.zig` / 동일 | 적용 안 함 / 적용 안 함 | `addGoBindings`의 유일한 사용자 옵션 구조이며 아키텍처가 이 경로를 명시한다. | 문서화된 사용자 API이므로 경로와 field는 호환성 대상이다. | **Conforms** |
| `GoBindings` | `build.zig:24:24` | `zigo-build.GoBindings` | build Go-binding feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `build.zig` / 동일 | 적용 안 함 / 적용 안 함 | `addGoBindings` 결과가 제공하는 build step 묶음이다. | 문서와 모든 예제가 field를 추론해 사용한다. | **Conforms** |
| `Change` | `src/gen/abi_diff.zig:5:20` | `abi_diff.Change` | ABI-diff feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/abi_diff.zig` / 동일 | 적용 안 함 / 적용 안 함 | 하나의 ABI 변화를 독립적으로 표현하며 `Report`는 이를 집계한다. | 내부 모듈 API다. | **Conforms** |
| `Report` (abi_diff) | `src/gen/abi_diff.zig:11:20` | `abi_diff.Report` | ABI-diff feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/abi_diff.zig` / 동일 | 적용 안 함 / 적용 안 함 | `diff` 반환값이며 deinit/render/hasBreaking 동작의 concrete owner다. | `src/main.zig`은 반환형을 추론한다. | **Conforms** |
| `Diagnostic` | `src/gen/diagnostic.zig:10:24` | `diagnostic.Diagnostic` | diagnostic feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/diagnostic.zig` / 동일 | 적용 안 함 / 적용 안 함 | validator가 반환하고 render/exit 동작을 소유하는 중심 타입이다. | `validate.findIssue`의 내부 모듈 반환 API다. | **Conforms** |
| `Options` (emit) | `src/gen/emit.zig:6:21` | `emit.Options` | emission feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/emit.zig` / 동일 | 적용 안 함 / 적용 안 함 | 모든 emitter render 함수가 공유하는 feature-level 설정이며 한 `Emitter` 인스턴스 상태에 종속되지 않는다. | generator가 `emit.Options`를 명시한다. | **Conforms** |
| `Emitter` | `src/gen/emit.zig:16:21` | `emit.Emitter` | emission feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/emit.zig` / 동일 | 적용 안 함 / 적용 안 함 | path/render 전략 한 쌍을 나타내며 `emit.all`의 원소 타입이다. | generator는 `emit.all`을 통해 소비한다. | **Conforms** |
| `Options` (generator) | `src/gen/generator.zig:9:21` | `generator.Options` | generator feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/generator.zig` / 동일 | 적용 안 함 / 적용 안 함 | `generate` 호출 전체를 설정하는 feature-level 타입이다. | main은 struct literal을 추론하지만 module test root에서도 공개가 적절하다. | **Conforms** |
| `AbiScalar` | `src/gen/ir/abi.zig:3:23` | `abi.AbiScalar` | ABI IR feature / 동일 | 고정 tagged union / 동일 | 공개 / 공개 | `src/gen/ir/abi.zig` / 동일 | 적용 안 함 / 적용 안 함 | lower와 emit 사이의 scalar ABI 표현의 중심 타입이다. | lower/emit이 경로를 직접 사용한다. | **Conforms** |
| `AbiParam` | `src/gen/ir/abi.zig:19:22` | `abi.AbiParam` | ABI IR feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/ir/abi.zig` / 동일 | 적용 안 함 / 적용 안 함 | ABI 함수 parameter record로 여러 lowering/emission 단계가 공유한다. | lower/emit이 경로를 직접 사용한다. | **Conforms** |
| `AbiParam.Role` | `src/gen/ir/abi.zig:25:22` | `abi.AbiParam.Role` | `AbiParam` / 동일 | 고정 enum / 동일 | 공개 / 공개 | `src/gen/ir/abi.zig` / 동일 | 적용 안 함 / 적용 안 함 | role은 구체 parameter의 ABI 역할에만 의미가 있어 이미 semantic owner 아래 있다. | 기존 내부 경로 유지. | **Conforms** |
| `ErrorCode` (abi) | `src/gen/ir/abi.zig:28:23` | `abi.ErrorCode` | ABI IR feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/ir/abi.zig` / 동일 | 적용 안 함 / 적용 안 함 | `AbiFn.errors`, `Program.error_codes`, lowering 입력이 공유하는 ABI-level code다. | generator/lower가 경로를 직접 사용한다. | **Conforms** |
| `AbiFn` | `src/gen/ir/abi.zig:30:19` | `abi.AbiFn` | ABI IR feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/ir/abi.zig` / 동일 | 적용 안 함 / 적용 안 함 | lowered function 한 개를 표현하고 semantic origin을 보존한다. | lower/emit이 직접 사용한다. | **Conforms** |
| `Program` | `src/gen/ir/abi.zig:38:21` | `abi.Program` | ABI IR feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/ir/abi.zig` / 동일 | 적용 안 함 / 적용 안 함 | 전체 lowered ABI program이며 emit 단계의 입력이다. | lower 반환/emit 입력으로 사용된다. | **Conforms** |
| `ErrorsLock` | `src/gen/ir/errors_lock.zig:8:24` | `errors_lock.ErrorsLock` | error-lock feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/ir/errors_lock.zig` / 동일 | 적용 안 함 / 적용 안 함 | parse/assign/validate/serialize와 allocation lifecycle을 소유한다. | generator와 tests가 경로를 직접 사용한다. | **Conforms** |
| `TypeNode` | `src/gen/ir/semantic.zig:33:22` | `semantic.TypeNode` | semantic IR feature / 동일 | 고정 tagged union / 동일 | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | recursive semantic type graph의 중심 node이며 여러 모듈이 직접 소비한다. | 내부 모듈 전반이 경로를 사용한다. | **Conforms** |
| `SemanticHint` | `src/gen/ir/semantic.zig:199:26` | `semantic.SemanticHint` | semantic IR feature / 동일 | 고정 enum / 동일 | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | parameter와 return 양쪽이 공유하므로 어느 한 concrete type보다 semantic feature가 좁은 공통 owner다. | ABI diff와 emit이 경로를 직접 사용한다. | **Conforms** |
| `Parameter` | `src/gen/ir/semantic.zig:202:23` | `semantic.Parameter` | semantic IR feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | reflection, validation, emission이 공유하는 semantic parameter record다. | 여러 내부 모듈이 직접 사용한다. | **Conforms** |
| `SemanticFn` | `src/gen/ir/semantic.zig:211:24` | `semantic.SemanticFn` | semantic IR feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | reflected function 한 개의 semantic record이며 여러 단계가 직접 소비한다. | 내부 모듈 전반이 직접 사용한다. | **Conforms** |
| `TypeDecl` | `src/gen/ir/semantic.zig:231:22` | `semantic.TypeDecl` | semantic IR feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | reflected named type declaration을 나타내며 reflection, ABI diff, emission이 공유한다. | 여러 내부 모듈이 직접 사용한다. | **Conforms** |
| `Constructor` | `src/gen/ir/semantic.zig:240:25` | `semantic.Constructor` | semantic IR feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | Semantic과 ABI Program이 공유하는 init/deinit/type 관계 record다. | reflect, abi, emit이 직접 사용한다. | **Conforms** |
| `Semantic` | `src/gen/ir/semantic.zig:246:22` | `semantic.Semantic` | semantic IR feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/ir/semantic.zig` / 동일 | 적용 안 함 / 적용 안 함 | serialized document root이며 parse/serialize 동작을 소유한다. | reflector/generator/main/tests가 직접 사용한다. | **Conforms** |
| `Difference` | `src/gen/sync_check.zig:4:24` | `sync_check.Difference` | generated-source comparison feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/sync_check.zig` / 동일 | 적용 안 함 / 적용 안 함 | 한 파일 차이를 독립적으로 표현하고 `Result`는 이를 집계한다. | 내부 모듈 API다. | **Conforms** |
| `Result` (sync_check) | `src/gen/sync_check.zig:6:20` | `sync_check.Result` | generated-source comparison feature / 동일 | 고정 struct / 동일 | 공개 / 공개 | `src/gen/sync_check.zig` / 동일 | 적용 안 함 / 적용 안 함 | compare 반환값이며 allocation cleanup, matches, render를 소유한다. | main은 반환형을 추론한다. | **Conforms** |

## Conforming file roots

파일 루트도 `ziglyzer --types`의 type entry이므로 빠뜨리지 않았다. 모두 인스턴스 field가 없는 namespace root이고 snake_case 파일명과 역할이 일치한다. visibility는 file root 자체 / 동일, declaration form은 namespace container / 동일, file form은 namespace root / 동일이다. 별도 compatibility alias는 없다.

| Type | Canonical implementation location | Confirmed public paths | Current owner / expected owner | Current physical location / expected physical location | Rationale | Compatibility constraints | Final assessment |
|---|---|---|---|---|---|---|---|
| `build` root | `build.zig:1:1` | `zigo-build` | package build API / 동일 | `build.zig` / 동일 | 사용자 build API namespace다. | dependency 이름은 소비자가 정한다. | **Conforms** |
| `abi_diff` root | `src/gen/abi_diff.zig:1:1` | `abi_diff` | ABI-diff feature / 동일 | 해당 파일 / 동일 | diff와 report 선언을 묶는다. | 내부 모듈. | **Conforms** |
| `diagnostic` root | `src/gen/diagnostic.zig:1:1` | `diagnostic` | diagnostic feature / 동일 | 해당 파일 / 동일 | 진단 선언을 묶는다. | 내부 모듈. | **Conforms** |
| `emit` root | `src/gen/emit.zig:1:1` | `emit` | emission feature / 동일 | 해당 파일 / 동일 | emitter와 render 구현을 묶는다. | 내부 path import. | **Conforms** |
| `generator` root | `src/gen/generator.zig:1:1` | `generator` | generator feature / 동일 | 해당 파일 / 동일 | generate orchestration을 묶는다. | CLI가 private import한다. | **Conforms** |
| `abi` root | `src/gen/ir/abi.zig:1:1` | `abi` | ABI IR feature / 동일 | 해당 파일 / 동일 | ABI IR 타입을 묶는다. | 내부 독립 모듈. | **Conforms** |
| `errors_lock` root | `src/gen/ir/errors_lock.zig:1:1` | `errors_lock` | error-lock feature / 동일 | 해당 파일 / 동일 | stable error mapping을 묶는다. | 내부 독립 모듈. | **Conforms** |
| `semantic` root | `src/gen/ir/semantic.zig:1:1` | `semantic` | semantic IR feature / 동일 | 해당 파일 / 동일 | semantic IR와 JSON 동작을 묶는다. | 내부 독립 모듈. | **Conforms** |
| `lower` root | `src/gen/lower.zig:1:1` | `lower` | lowering feature / 동일 | 해당 파일 / 동일 | semantic-to-ABI 변환 함수 namespace다. | 내부 path import. | **Conforms** |
| `naming` root | `src/gen/naming.zig:1:1` | `naming` | naming feature / 동일 | 해당 파일 / 동일 | 이름 변환 함수를 묶는다. | 내부 path import. | **Conforms** |
| `sync_check` root | `src/gen/sync_check.zig:1:1` | `sync_check` | generated-source comparison / 동일 | 해당 파일 / 동일 | compare/result를 묶는다. | 내부 독립 모듈. | **Conforms** |
| `validate` root | `src/gen/validate.zig:1:1` | `validate` | semantic validation / 동일 | 해당 파일 / 동일 | validation 함수 namespace다. | 내부 path import. | **Conforms** |
| `zigo-cli` main root | `src/main.zig:1:1` | `zigo-cli` | generator CLI / 동일 | 해당 파일 / 동일 | 실행 진입점과 CLI 보조 함수를 묶는다. | 조사용 root 이름이며 패키지 type API가 아니다. | **Conforms** |
| `zigo-reflect` main root | `src/reflect/main.zig:1:1` | `zigo-reflect` | reflector CLI / 동일 | 해당 파일 / 동일 | reflector 실행 진입점이다. | 내부 executable root. | **Conforms** |
| `reflect_names` root | `src/reflect/names.zig:1:1` | `reflect_names` | reflection naming / 동일 | 해당 파일 / 동일 | AST 기반 이름 보강을 묶는다. | 내부 독립 test module 및 path import. | **Conforms** |
| `reflect_walk` root | `src/reflect/walk.zig:1:1` | `reflect_walk` | reflection walk / 동일 | 해당 파일 / 동일 | comptime reflection walk를 묶는다. | 내부 독립 test module 및 path import. | **Conforms** |
| `zigo` root | `src/root.zig:1:1` | `zigo` | public declaration DSL / 동일 | 해당 파일 / 동일 | 사용자-facing `define` namespace다. | 문서화된 공개 module root. | **Conforms** |

## Conforming local, anonymous, and factory bodies

이 표의 visibility는 모두 private / private, public paths는 없음, 물리 위치는 현재 lexical owner와 동일, split-file form은 적용 대상이 아니다. 테스트 전용 타입을 생산 API owner로 승격하지 않는 것이 의도에 맞다.

| Type | Canonical implementation location | Confirmed public paths | Current owner / expected owner | Current declaration form / expected declaration form | Rationale | Compatibility constraints | Final assessment |
|---|---|---|---|---|---|---|---|
| scalar expected-file row | `src/gen/generator.zig:99:25` | 없음 | scalar generation test / 동일 | 익명 고정 struct / 동일 | path/content test table의 행에만 의미가 있다. | 없음. | **Conforms** |
| invalid-output existing-file row | `src/gen/generator.zig:287:25` | 없음 | ZIGO003 no-write test / 동일 | 익명 고정 struct / 동일 | path/content test fixture의 행이다. | 없음. | **Conforms** |
| pointer payload | `src/gen/ir/abi.zig:12:14` | 없음 | `AbiScalar.pointer` variant / 동일 | 익명 고정 struct / 동일 | child/const/many는 pointer variant에만 의미가 있고 이미 inline owner에 있다. | ABI union field 모양은 테스트 대상이다. | **Conforms** |
| initialism table row | `src/gen/naming.zig:42:22` | 없음 | `initialism` helper / 동일 | 익명 고정 struct / 동일 | 함수 내부 lookup row다. | 없음. | **Conforms** |
| naming test case | `src/gen/naming.zig:52:22` | 없음 | naming test / 동일 | 익명 고정 struct / 동일 | input/snake/pascal 기대값에만 의미가 있다. | 없음. | **Conforms** |
| difference comparator | `src/gen/sync_check.zig:46:60` | 없음 | `compare` sort call / 동일 | 익명 고정 namespace struct / 동일 | private `lessThan` 함수의 lexical container다. | 없음. | **Conforms** |
| validation snapshot case | `src/gen/validate.zig:200:22` | 없음 | diagnostic snapshot test / 동일 | 익명 고정 struct / 동일 | document/snapshot fixture row다. | 없음. | **Conforms** |
| scalar reflection callback container | `src/reflect/walk.zig:314:17` | 없음 | scalar reflection test / 동일 | 익명 고정 namespace struct / 동일 | local `call` function을 값으로 선택하기 위한 test container다. | 없음. | **Conforms** |
| `Fixture` | `src/reflect/walk.zig:386:21` | 없음 | invalid-declaration reflection test / 동일 | 고정 namespace struct / 동일 | 세 test function과 subordinate `Value`를 묶는 lexical test owner다. | 없음. | **Conforms** |
| `Fixture.Value` | `src/reflect/walk.zig:387:23` | 없음 | `Fixture` / 동일 | 고정 tagged union / 동일 | `Fixture.tagged`의 구체 test context에 이미 중첩됐다. | 없음. | **Conforms** |
| `Generic` | `src/reflect/walk.zig:415:21` | 없음 | named-specialization test / 동일 | 고정 namespace struct / 동일 | private type factory를 묶는 test namespace다. | 없음. | **Conforms** |
| `Generic.Buffer` | `src/reflect/walk.zig:416:12` (returned body `:417:20`) | local aliases `FloatBuffer`, `IntBuffer`; public path 없음 | `Generic` / 동일 | named type factory / 동일 | 조성이 comptime `T`에 의존하고 서로 다른 specialization을 만든다. AST는 `:417` 익명 struct만 기록했지만 함수 반환형과 두 호출로 factory임을 확인했다. | `FloatBuffer = Generic.Buffer(f32)`와 `IntBuffer = Generic.Buffer(i32)`는 canonical이 아닌 test-local aliases다. | **Conforms** |
| declaration-DSL callback container | `src/root.zig:9:17` | 없음 | `define` test / 동일 | 익명 고정 namespace struct / 동일 | local `call` function을 declaration tuple에 넣기 위한 test container다. | 없음. | **Conforms** |

## Alias, visibility, and compatibility findings

- 생산 범위의 `pub const` type declaration은 모두 직접 type body다. 다른 이름만 가리키는 생산 alias와 중복 공개 경로는 없다.
- `ziglyzer` AST가 alias로 확정하지 못한 계산식은 `FloatBuffer = Generic.Buffer(f32)`와 `IntBuffer = Generic.Buffer(i32)` 두 개다. 둘 다 private test alias이며 canonical implementation은 `Generic.Buffer` type-factory body다.
- `build.zig`의 네 named type은 사용자 build API에 속한다. 특히 `Options`와 `GoBindings`는 문서와 예제에서 계약으로 다뤄진다.
- `semantic`, `abi`, generator 계열 타입의 `pub`는 독립 Zig module 경계를 넘기 위한 visibility다. 아키텍처상 package 사용자 공개 API는 아니다.
- improvement candidate를 실제로 변경할 때 build API의 이전 경로는 compatibility alias로 보존해야 한다. 내부 모듈 경로는 한 커밋에서 모든 소비자를 갱신할 수 있지만, downstream 도구가 내부 module을 직접 import할 가능성까지 보호하려면 한 릴리스 동안 alias를 유지할 수 있다.

## Import-cycle and consumer check

현재 import 방향은 `semantic`이 leaf이고, `abi -> semantic`, `abi_diff -> semantic`, `validate -> semantic + diagnostic`, `lower/emit -> abi + semantic`, `generator -> emit + abi + errors_lock + lower + semantic + validate`, CLI가 이 모듈들을 조립하는 방향이다. 후보 22개는 모두 기존 파일 안에서 중첩하므로 새 import가 생기지 않고 cycle 위험이 없다.

기존 경로 소비도 확인했다.

- 문서/예제: `zigo.addGoBindings`와 inferred `Options` literal, `GoBindings` fields를 사용한다.
- tests: `semantic.Semantic`, `errors_lock.ErrorsLock`를 직접 사용한다.
- source: `semantic.Callback`, `semantic.SemanticHint`, `semantic.TypeKind`, `semantic.TypeField` 등 후보 경로 일부를 명시적으로 사용한다.
- public root `src/root.zig`에는 named type이 없고 `zigo.define`만 있다.

## Final check

- [x] canonical implementation과 alias를 구분했다.
- [x] semantic owner와 lexical nesting을 구분했다.
- [x] build root, package root, CLI root, 독립 내부 module root별 공개 경로를 확인했다.
- [x] owner, declaration form, visibility, physical location을 독립적으로 평가했다.
- [x] 이동 후보의 import-cycle 위험을 확인했다.
- [x] 사용자 build API와 내부 module API를 나눠 compatibility 전략을 제시했다.
- [x] 기존 경로를 사용하는 source, tests, docs, examples를 검색했다.
- [x] placement assessment와 소스 변경 결정을 분리했으며 생산 Zig 소스는 변경하지 않았다.
