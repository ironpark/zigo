# 큰 API의 자동 발견

하나의 opaque `TelemetryHub`에 많은 함수를 모아 public 함수 자동 발견과 필요한 선언만
보강하는 방식을 보여 주는 통합 예제입니다.

## 실행

```sh
zig build test go-check abi-check go-coverage go-report
zig build go
(cd go && go test -count=1 ./...)

zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test -count=1 ./...)
```

## 핵심 파일

- [src/root.zig](src/root.zig) — 큰 공개 API와 상태 객체
- [src/bindings.zig](src/bindings.zig) — `.discovery.public`과 명시적 보강
- [build.zig](build.zig) — custom raw package와 purego 설치 경로
- `go/internal/native` — 이 예제의 raw package

## 생성되는 동작

일반 함수는 자동 발견하고 문자열, callback과 취소처럼 별도 계약이 필요한 네 함수만 Context에서
보강합니다. enum, typed error, retained observer, slice, 통계와 제자리 변환을 한 package에
조합합니다. 함수 수와 생성 줄 수 대신 `go-coverage`로 누락을, `go-report`로 최종 결정을
검사하세요. `TelemetryHub` 자체는 thread-safe하지 않습니다.

## 다음 문서

[함수와 패키지](../../docs/authoring/functions-and-packages.md) ·
[생성물과 CI](../../docs/build-and-ship/generated-files-and-ci.md) ·
[예제 선택](../../docs/examples.md)
