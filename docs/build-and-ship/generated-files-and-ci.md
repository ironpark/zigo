# 생성물과 CI

이 가이드는 생성 파일을 갱신하고 검토·커밋하며 CI에서 오래된 생성물을 찾는 흐름을
설명합니다.

## 개발 순서

Zig API 또는 `bindings.zig`를 바꾼 뒤 실행합니다.

```bash
zig build go
(cd go && go test ./...)
git diff
```

`*_gen.go`를 직접 고치지 마세요. 공개 패키지에 편의 API가 필요하면 `_gen.go`가 아닌
별도 사용자 파일을 같은 패키지에 추가합니다.

## 무엇을 커밋하나요?

| 위치 | 내용 | 커밋 |
|---|---|---|
| `go/**/*_gen.go` | 공개, raw와 lifecycle Go code | 예 |
| `go/go.mod`, `go/go.sum` | Go 모듈과 의존성 | 예 |
| `zigo/go/semantic.json` | 선택·타입·수명 계약 | 예 |
| `zigo/go/errors.lock.json` | Zig 오류와 안정된 코드 대응 | 예 |
| `**/zigo_link_inputs_gen.go` | 머신별 정적 링크 입력 | 아니요 |
| `zig-out/`, `.zig-cache/` | 빌드 산출물과 캐시 | 아니요 |

권장 `.gitignore`는 다음과 같습니다.

```gitignore
**/zigo_link_inputs_gen.go
zig-out/
.zig-cache/
```

Rust 바인딩 set은 같은 두 파일을 `zigo/rust/` 아래에 둡니다.

generator는 자신의 marker가 있는 오래된 파일만 정리합니다. 사용자가 작성한 Go 파일은
보존합니다. `go_dir` 자체를 옮겼다면 이전 디렉터리는 자동 정리 범위 밖이므로 내용을 확인한
뒤 직접 정리해야 합니다.

## 표준 빌드 단계

| 단계 | 역할 | 소스 트리 변경 |
|---|---|---|
| `go` | 생성물 갱신, 네이티브 라이브러리와 헤더 설치 | 예 |
| `go-check` | 커밋된 생성물과 현재 결과 비교 | 링크 입력 파일만 가능 |
| `go-lib` | 네이티브 라이브러리와 헤더 설치 | 링크 입력 파일만 가능 |
| `go-doctor` | Go, 포매터, 컴파일러와 loader 전제 검사 | 아니요 |
| `go-report` | 최종 이름, 패키지, 소유권 결정 출력 | 아니요 |
| `go-coverage` | 공개 Zig API의 bound/excluded/unbound 보고 | `-Dcoverage-json=<path>` 지정 시 JSON 기록 |
| `go-abi-check` | `abi_base`와 호환성 비교 | 아니요 |
| `go-verify` | check, lib, doctor와 선택적 ABI 검사 집계 | 링크 입력 파일만 가능 |

`go-verify`는 Go 테스트를 실행하지 않습니다. `standard_steps = .{ .variant = "purego" }`처럼
variant를 붙인 바인딩 set은 `go-purego`, `go-purego-check`, `go-purego-abi-check`처럼 언어 토큰
뒤에 variant가 들어간 이름으로 같은 단계를 등록하고, coverage JSON 옵션은
`-Dpurego-coverage-json`이 됩니다. Rust 바인딩 set은 `rust`, `rust-check`, `rust-lib`,
`rust-coverage`, `rust-abi-check`를 등록합니다.

## CI 구성

새 checkout에서 다음 순서로 실행하는 구성이 기본입니다.

```bash
zig build go-verify --summary all
(cd go && go test ./...)
```

`abi_base = null`이면 `go-verify`는 ABI 비교를 생략합니다. 단순히 오래된 생성물과 네이티브
링크만 확인하려면 다음처럼 분리할 수 있습니다.

```bash
zig build go-check go-lib --summary all
(cd go && go test ./...)
```

CI에서 `go`를 먼저 실행하면 누락된 커밋을 고쳐 버릴 수 있으므로 최신 상태 검사는 반드시
`go-check`로 수행하세요.

## ABI 기준

기본값 `"HEAD"`는 마지막 커밋의 `zigo/go/semantic.json`과 비교합니다. 독립 배포한 이전 릴리스와
호환성을 유지할 때는 그 릴리스의 Git ref를 설정합니다.

```zig
.abi_base = "v1.2.0",
```

```bash
zig build go-abi-check
```

오류 코드, C 심볼, 타입 배치, 소유권과 콜백 계약 변경이 비교 대상입니다. 같은
저장소에서 Go와 네이티브 산출물을 항상 함께 배포하고 이전 ABI 소비자가 없다면
`.abi_base = null`로 검사를 끌 수 있습니다.

C 선언이 그대로여도 Go 호출부만 바뀌는 변경은 `Go parameter surface changed`로 따로
보고합니다. 예를 들어 옵션 구조체의 필드를 구조체 밖 매개변수로 옮기면 C가 보는 타입과
순서는 같고 Go 호출자만 인자를 하나 더 적어야 합니다.

## 문제를 찾는 명령

| 증상 | 명령 |
|---|---|
| 도구나 라이브러리가 준비되지 않음 | `zig build go-doctor` |
| 생성 이름이나 소유권이 예상과 다름 | `zig build go-report` |
| 새 공개 Zig 함수가 누락됨 | `zig build go-coverage` |
| 생성물이 오래됨 | `zig build go-check` |
| 생성 중 `ZIGO...` 오류 | [진단 참조](../reference/diagnostics.md) |

생성 검증이나 렌더링이 실패하면 기존 출력 tree는 유지됩니다. 파일 쓰기 자체가
중단된 경우에는 다시 `zig build go`를 실행하고 전체 diff를 확인하세요.
