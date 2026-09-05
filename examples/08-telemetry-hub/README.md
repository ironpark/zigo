# 큰 API의 자동 발견

하나의 opaque `TelemetryHub`에 여러 API를 모아 자동 발견과 생성기의 처리 범위를
검증합니다. 작은 기능 하나를 배우려면 [예제 선택 가이드](../../docs/examples.md)에서
더 단순한 예제를 먼저 선택하세요.

## 확인할 기능

- 여러 enum과 typed error set
- 소유한 UTF-8 설정과 retained Go observer
- scalar·slice 입력과 두 가지 overflow 정책
- 처리 모드, 필터, 카운터, 통계, 조회와 제자리 변환
- 생성 실패 정리, batch 거부, 콜백 panic과 독립 객체의 동시 사용
- `go/internal/native`의 사용자 지정 raw 패키지
- purego 자동 내부 로더와 사용자 지정 설치 경로

`bindings.zig`는 일반 함수를 자동 발견하고 문자열·콜백 등 별도 계약이 필요한 선언만
보강합니다. 함수 개수와 생성 줄 수는 변경될 수 있으므로 `go-coverage`와 `go-report`로
현재 결과를 확인하세요.

## 실행

이 디렉터리에서 실행합니다.

```sh
zig build test go-check abi-check go-coverage go-report
zig build go
(cd go && go test -count=1 ./...)

zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test -count=1 ./...)
```

Hub 자체는 동시 호출에 안전하지 않습니다. 동시성 테스트는 goroutine마다 다른 Hub를
사용합니다. 자동 발견 설정은 [함수와 패키지](../../docs/bindings-functions.md)를 참고하세요.
