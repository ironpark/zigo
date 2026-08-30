# 프로젝트 개발

## 기본 검증

저장소 루트에서 Zig 단위 테스트와 스냅샷 하네스를 실행한다.

```bash
zig build test --summary all
```

각 예제는 독립 Zig/Go 프로젝트다. 생성물 동기화, ABI와 Go 동작을 함께 검사한다.

```bash
for example in examples/*; do
  (cd "$example" && zig build go-check abi-check)
  (cd "$example/go" && go test ./...)
done
```

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
