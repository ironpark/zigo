# 생성물과 CI

이 가이드는 생성 파일을 갱신하고 review·commit하며 CI에서 stale output을 찾는 흐름을
설명합니다.

## 개발 순서

Zig API 또는 `bindings.zig`를 바꾼 뒤 실행합니다.

```bash
zig build go
(cd go && go test ./...)
git diff
```

`*_gen.go`를 직접 고치지 마세요. public package에 편의 API가 필요하면 `_gen.go`가 아닌
별도 사용자 파일을 같은 package에 추가합니다.

## 무엇을 커밋하나요?

| 위치 | 내용 | 커밋 |
|---|---|---|
| `go/**/*_gen.go` | public, raw와 lifecycle Go code | 예 |
| `go/go.mod`, `go/go.sum` | Go module과 dependency | 예 |
| `zigo/semantic.json` | 선택·타입·수명 계약 | 예 |
| `zigo/errors.lock.json` | Zig error와 안정된 code 대응 | 예 |
| `**/zigo_link_inputs_gen.go` | machine-local static link input | 아니요 |
| `zig-out/`, `.zig-cache/` | build artifact와 cache | 아니요 |

권장 `.gitignore`는 다음과 같습니다.

```gitignore
**/zigo_link_inputs_gen.go
zig-out/
.zig-cache/
```

generator는 자신의 marker가 있는 오래된 파일만 정리합니다. 사용자가 작성한 Go 파일은
보존합니다. `go_dir` 자체를 옮겼다면 이전 디렉터리는 자동 정리 범위 밖이므로 내용을 확인한
뒤 직접 정리해야 합니다.

## standard step

| step | 역할 | source tree 변경 |
|---|---|---|
| `go` | 생성물 갱신, native library와 header 설치 | 예 |
| `go-check` | 커밋된 생성물과 현재 결과 비교 | link input 파일만 가능 |
| `go-lib` | native library와 header 설치 | link input 파일만 가능 |
| `go-doctor` | Go, formatter, compiler와 loader 전제 검사 | 아니요 |
| `go-report` | 최종 이름, package, ownership 결정 출력 | 아니요 |
| `go-coverage` | 공개 Zig API의 bound/excluded/unbound 보고 | 설정 시 JSON 기록 |
| `abi-check` | `abi_base`와 호환성 비교 | 아니요 |
| `go-verify` | check, lib, doctor와 선택적 ABI 검사 집계 | link input 파일만 가능 |

`go-verify`는 Go test를 실행하지 않습니다.

## CI 구성

새 checkout에서 다음 순서로 실행하는 구성이 기본입니다.

```bash
zig build go-verify --summary all
(cd go && go test ./...)
```

`abi_base`가 없다면 `go-verify`는 ABI 비교를 생략합니다. 단순히 stale 생성물과 native
link만 확인하려면 다음처럼 분리할 수 있습니다.

```bash
zig build go-check go-lib --summary all
(cd go && go test ./...)
```

CI에서 `go`를 먼저 실행하면 누락된 커밋을 고쳐 버릴 수 있으므로 stale 검사는 반드시
`go-check`로 수행하세요.

## ABI 기준

독립 배포한 이전 release와 호환성을 유지할 때만 Git ref를 설정합니다.

```zig
.abi_base = "HEAD^",
```

```bash
zig build abi-check
```

error code, C symbol, type layout, ownership과 callback contract 변경이 비교 대상입니다. 같은
저장소에서 Go와 native artifact를 항상 함께 배포하고 이전 ABI 소비자가 없다면 필수 설정이
아닙니다.

## 문제를 찾는 명령

| 증상 | 명령 |
|---|---|
| 도구나 library가 준비되지 않음 | `zig build go-doctor` |
| 생성 이름이나 ownership이 예상과 다름 | `zig build go-report` |
| 새 public Zig 함수가 누락됨 | `zig build go-coverage` |
| 생성물이 stale함 | `zig build go-check` |
| 생성 중 `ZIGO...` 오류 | [진단 참조](../reference/diagnostics.md) |

생성 validation이나 rendering이 실패하면 기존 output tree는 유지됩니다. 파일 쓰기 자체가
중단된 경우에는 다시 `zig build go`를 실행하고 전체 diff를 확인하세요.
