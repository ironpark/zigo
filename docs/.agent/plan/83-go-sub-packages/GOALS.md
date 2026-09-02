# GOALS

## Problem and the end result from the user's point of view

생성되는 공개 Go 패키지는 항상 하나다. 실제 규모의 라이브러리(libghostty-vt: terminal, stream, charset, 유틸리티 namespace)를 바인딩하면 수십 개 타입과 함수가 한 패키지에 평탄하게 놓이고, `text.unicode.codepointWidth`처럼 namespace가 있어도 Go 이름에서는 사라진다. 특정 타입이나 함수 묶음을 별도 패키지(`vt/stream`, `vt/text`)로 내보낼 방법이 없다.

끝난 뒤: 바인딩 선언에 `.packages`를 적어 타입(그 타입의 메서드·생성자 포함), namespace, 개별 함수를 하위 패키지에 배정할 수 있다. 배정되지 않은 것은 기본 공개 패키지에 남는다. 패키지 사이에서 handle·enum·struct를 자유롭게 주고받을 수 있고, import 순환은 생성 전에 진단된다. cgo·purego 모두 지원한다.

## Measurable goals

- 예제 하나를 두 공개 패키지(기본 + 하위)로 나눠 cgo·purego에서 통과: 하위 패키지의 handle을 기본 패키지 메서드가 반환하고, 하위 패키지 함수가 기본 패키지의 enum/struct를 받는다.
- `.packages`가 없는 모든 기존 예제의 생성물이 바이트 동일하다.
- import 순환을 만드는 배정은 `ZIGO0xx`로 거부되고 순환 경로를 힌트에 적는다.
- 각 패키지가 자기 godoc(`// Package …`)과 `errors.Is`가 통하는 오류 sentinel을 가진다.

## Supported scope and non-goals

- 범위: 바인딩 선언 `.packages`, reflection과 semantic.json(`package` 배정), 공용 lifecycle 런타임 패키지, 패키지별 emit(cgo·purego), 순환·이름 충돌 진단, abi_diff, go-check/stale 정리, 예제, 문서, CHANGELOG.
- 비범위: `go_dir` 밖의 패키지, 별도 Go 모듈로 분리, raw 패키지 분할(raw는 하나로 유지), 패키지별 다른 네이티브 라이브러리.

## Reference source / commit / license

`src/root.zig`(DSL), `src/reflect/walk.zig`(선언 처리), `src/gen/emit.zig`(`renderGoEnums`, handle/runtime/errors 파일 emit, `zigoCheckedPointer` 등 비공개 헬퍼), `examples/07-event-queue/go-purego/internal/native`(purego의 공용 내부 패키지 선례), `build.zig`(`go_package_path`, `PublishGeneratedGo`, stale 정리, 플랜 76), `docs/bindings.md:36-63`(namespace와 Go 이름), `docs/configuration.md`. 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹색, CHANGELOG Unreleased Added.
