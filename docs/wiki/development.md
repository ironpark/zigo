# 프로젝트 개발

## 기본 검증

저장소 루트에서 Zig 단위 테스트와 스냅샷 하네스를 실행한다.

```bash
zig build test --summary all
```

각 예제는 독립 Zig/Go 프로젝트다. 생성물 동기화, ABI와 Go 동작을 함께 검사한다.

```bash
for example in examples/*; do
  (cd "$example" && zig build test go-check abi-check --summary all)
  (cd "$example/go" && go test ./...)
done
```

## purego 백엔드 검증

purego 바인딩을 가진 예제는 별도 스텝으로 생성하고, C 컴파일러 없이 테스트한다.

```bash
for example in examples/04-callback examples/07-event-queue examples/08-telemetry-hub; do
  (cd "$example" && zig build purego-go purego-go-verify --summary all)
  (cd "$example/go-purego" && CGO_ENABLED=0 go test ./...)
done

(cd examples/10-tagged-union && zig build go go-verify -Dpurego --summary all)
```

두 백엔드를 등록한 예제는 정적 아카이브와 공유 라이브러리가 같은 `zig-out`에 설치되지만
서로를 가리지 않는다. cgo 생성물은 아카이브를 경로로 직접 링크하고 purego 헤더는
별도 이름으로 설치되므로, 두 백엔드를 순서에 상관없이 한 트리에서 검증할 수 있다.
생성된 purego 테스트는 `ZIGO_LIBRARY_PATH`가 있으면 그 경로를 우선 사용한다.

`examples/10-tagged-union`의 purego 테스트는 `ZIGO_TEST_LIBRARY`에 설치된 라이브러리의
절대 경로를 요구하며, `ZIGO_TEST_WRONG_LIBRARY`를 함께 주면 심볼 누락 실패 경로까지
검증한다. 설정하지 않으면 skip한다.

설치된 아티팩트 자체는 저장소 도구로 검사한다.

```bash
tests/inspect_shared_library.sh \
  examples/04-callback/zig-out/lib/libcallback_zigo.dylib zg_last_error_message
zig build shared-library-smoke -- \
  examples/04-callback/zig-out/lib/libcallback_zigo.dylib zg_last_error_message
```

생성된 purego 로더는 플랫폼 파일명을 실행 시점에 고르므로 macOS와 Linux에서 생성물이
동일해야 한다. CI는 두 OS의 amd64·arm64에서 이 동일성과 `CGO_ENABLED=0` 테스트를 함께
검사한다.

## 통합 예제

[`examples/05-pipeline`](../../examples/05-pipeline/README.md)은 opaque 객체, 에러,
슬라이스, enum, generic specialization, retained 콜백과 system library 전파를 한 번에
검증한다.

[`examples/07-event-queue`](../../examples/07-event-queue/README.md)은 고정 용량 상태,
UTF-8 메타데이터, enum 정책, typed error, retained observer와 custom raw package 경로를
애플리케이션 형태로 검증한다.

[`examples/08-telemetry-hub`](../../examples/08-telemetry-hub/README.md)은 하나의 opaque
타입에 51개 함수를 노출한다. 대형 declaration의 comptime reflection, 세 enum, 여러 error
set, UTF-8 소유 상태, slice 입력, retained callback, 조회·통계·변환 API를 함께 검증하는
생성기 폭(breadth) 회귀 fixture다.

[`examples/09-type-relations`](../../examples/09-type-relations/README.md)은 두 opaque 타입을
동시에 노출하고 `Accumulator` receiver가 `*Counter`를 받는 교차 타입 API와 독립 lifecycle을
검증한다.

[`examples/10-tagged-union`](../../examples/10-tagged-union/README.md)은 tagged union을 opaque
handle로 유지하면서 자동 생성된 tag와 checked payload accessor를 owned/borrowed Go wrapper,
scalar·enum·slice·다른 handle payload에 걸쳐 검증한다.

```bash
cd examples/05-pipeline
zig build test
zig build go
zig build go-check abi-check
cd go && go test -count=1 ./...
```

event queue 예제도 동일하게 실행한다.

```bash
cd examples/07-event-queue
zig build test
zig build go-check abi-check
cd go && go test -count=1 ./...
```

대형 API의 reflection과 생성 비용까지 확인할 때는 telemetry hub 예제를 실행한다.

```bash
cd examples/08-telemetry-hub
zig build test
zig build go-check abi-check
cd go && go test -count=1 ./...
```

## 문서 변경 확인

사용자 문서의 명령과 Zig 예제는 현재 `examples/`와 `build.zig`의 공개 옵션을 기준으로
유지한다. 내부 동작이나 지원 범위를 바꾸면 [사용자 위키](README.md)와
[설계 문서](../design/README.md)를 함께 갱신한다.
