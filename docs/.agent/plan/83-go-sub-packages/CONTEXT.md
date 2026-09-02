# SCOPE

- **선언**: `zigo.define(.{ ..., .packages = .{ .{ .path = "stream", .name = "stream", .doc = "…", .types = .{"Stream"}, .namespaces = .{"text", "text.unicode"}, .functions = .{"root.liveObjects"} }, … } })`. `.path`는 `go_package_path` 기준 상대 경로(`raw_package`와 같은 검증), `.name`은 Go 식별자(기본값: path의 마지막 요소 snake). 배정 우선순위: 함수 명시 > 타입 소유(receiver 또는 `go_owner`) > namespace(가장 긴 접두 일치) > 기본 패키지. 타입의 메서드·생성자·소멸자·projection은 타입을 따르며 함수 명시로 떼어낼 수 없다(진단).
- **semantic.json**: `packages: [{path, name, doc}]`와 각 `TypeDecl`/`SemanticFn`의 `package: "<name>"`(기본 패키지면 생략). 스키마 확장은 생략 규칙으로 기존 문서 불변.
- **공용 런타임**: 생성 트리에 `internal/<raw>/…` 옆 `internal/lifecycle`(이름은 phase 1에서 확정) 패키지를 두고 지금 패키지마다 비공개로 찍던 것을 exported로 옮긴다: handle 인터페이스, `CheckedPointer`/`OptionalPointer`/`PoisonAfterPanic`, `NativePanicError`, 오류 코드→오류 변환, `RangeError`, `CallbackError`, 스트림 어댑터, 취소 플래그. 각 공개 패키지는 `type NativePanicError = lifecycle.NativePanicError`, `var ErrClosed = lifecycle.ErrClosed`처럼 alias/재선언으로 자기 표면을 유지해 **단일 패키지일 때의 공개 API가 바뀌지 않는다**. handle 구조체는 소유 패키지에서 정의하고 exported 인터페이스를 구현한다.
- **패키지 간 참조**: 타입 참조는 `import "<module>/<path>"` + 한정 이름. import 목록은 참조 그래프에서 계산. 순환은 진단(새 ZIGO 코드).
- **이름 충돌 검사(ZIGO024)**는 패키지 단위로.
- **purego**: `internal/native`는 심볼 로더·네이티브 함수 테이블·콜백 토큰 레지스트리와 트램폴린 상태를 계속 소유한다. `internal/lifecycle`은 백엔드와 무관한 핸들 계약·오류 형식·스트림/취소 공용 도우미만 소유하며, purego 공개 패키지는 필요한 경우 두 internal 패키지를 모두 import한다.
- **build.zig**: 패키지별 출력 디렉터리, stale 정리가 모든 패키지 디렉터리를 포함, `go_package_doc`은 기본 패키지용이고 하위 패키지 doc은 선언의 `.doc`.
- **abi_diff**: 패키지 배정 변경은 Go 표면 breaking.
- **예제**: 09-type-relations(namespace `text.unicode`, handle 둘, enum/struct)를 `text` 하위 패키지로 나누거나 07에 적용해 cgo·purego 커버.
- **문서**: `docs/bindings.md`(`.packages` 절), `docs/configuration.md`, `docs/generated-code.md`(트리·공용 런타임), `docs/limitations.md`, CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- 공개 패키지 파일: `<pkg>_gen.go`, `_enums_gen.go`, `_errors_gen.go`, `_handles_gen.go`, `_runtime_gen.go`, `_structs_gen.go`. lifecycle 헬퍼와 오류는 모두 패키지 비공개다.
- handle 구조체(`ptr, mu, active, closed, poison, cleanup`)는 패키지 안에서 직접 필드를 만진다. 다른 패키지의 handle을 인자로 받으려면 exported 접근이 필요하다.
- namespace는 Go 이름에서 제거된다(`CodepointWidth`). 같은 이름 충돌은 `.name`으로 푼다.
- purego는 `internal/native`에 로더·심볼 테이블·콜백 레지스트리를 exported로 두고 공개 패키지가 쓴다. cgo에는 대응물이 없다.
- `go-check`/stale 정리는 `go_dir` 전체를 마커 기준으로 걷는다(플랜 76).

## Target structure and invariants

- 기본 패키지 하나 + 0개 이상의 하위 패키지. 모두 `go_dir` 아래, 모두 같은 raw/native/lifecycle 내부 패키지를 쓴다.
- 공용 런타임은 `.packages`가 하나라도 선언된 바인딩에서만 활성화한다. `.packages`가 없는 단일 패키지 바인딩은 기존 생성물을 바이트 단위로 유지한다. 활성화된 경우 공개 패키지는 `internal/lifecycle`의 형식 alias와 sentinel 변수를 재선언해 기존 공개 API 이름을 유지한다.
- 패키지 간 의존은 DAG여야 하며, 진단은 순환에 참여하는 선언을 이름으로 적는다.
- 타입과 그 메서드는 한 패키지에 있다.

## Implemented decisions and deviations

- 교차 패키지 import는 선언된 package name을 그대로 노출하지 않고 생성기 전용 alias
  `zigo_pkg_<name>`(기본 패키지는 `zigo_default`)를 사용한다. 사용자 파라미터나 표준 패키지
  이름과의 우연한 충돌을 피하면서 모든 타입 참조는 명시적으로 한정된다.
- cgo와 purego 모두 `.packages`가 있을 때만 `internal/lifecycle`을 생성한다. purego의
  loader/function table/callback registry는 raw로 설정한 `internal/native`에 남는다.
- 최초 계획의 “stream adapters, cancel flag를 lifecycle로 이동”은 구현 중 범위를 좁혔다.
  공유 identity와 package 간 호출에 필요한 handle 계약·pointer 검사·poison·오류 형식은
  lifecycle이 소유하지만, stream callback 연결과 cancel word는 각 호출 wrapper의 package-local
  코드로 유지한다. 둘은 호출마다 생성되고 raw callback registry에 직접 연결되어 공유 상태나
  package 간 타입 identity가 없으므로 옮기면 오히려 lifecycle이 backend raw 계층에 의존한다.
- 예제 07은 의존 방향을 기본 패키지 → `types` 하나로 유지한다. `QueueSignal`, `Ticker`,
  `TickerInfo`를 옮기고 기본 패키지의 `EchoQueueSignal`/`InspectTicker`가 enum, handle, struct를
  참조한다. 반대 방향 참조도 동시에 넣으면 의도적으로 금지한 Go import cycle이 되므로 넣지
  않았다.
