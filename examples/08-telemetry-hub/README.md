# 큰 API의 자동 발견

하나의 opaque `TelemetryHub`에 많은 함수를 모아 공개 함수 자동 발견과 필요한 선언만
보강하는 방식을 보여 주는 통합 예제입니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다.
purego 테스트도 Zig로 빌드한 공유 라이브러리를 사용합니다. 로드 설정은 이 예제에 포함되어 있습니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

## 실행

```sh
zig build go
zig build go-coverage go-report
(cd go && go test -count=1 ./...)

zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test -count=1 ./...)
```

## 예상 결과

cgo·purego 테스트가 통과합니다. `go-coverage`는 바인딩 포함·제외·누락을,
`go-report`는 이름과 계약을 출력합니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — 큰 공개 API와 상태 객체
- [src/bindings.zig](src/bindings.zig) — `.discovery.public`과 명시적 보강
- [빌드.zig](build.zig) — 사용자 지정 raw 패키지와 purego 설치 경로
- `go/internal/native` — 이 예제의 raw 패키지

## 동작과 주의사항

일반 함수는 자동 발견하고 문자열, 콜백과 취소처럼 별도 계약이 필요한 네 함수만 Context에서
보강합니다. 열거형, typed error, retained observer, 슬라이스, 통계와 제자리 변환을 한 패키지에
조합합니다. 함수 수와 생성 줄 수 대신 `go-coverage`로 누락을, `go-report`로 최종 결정을
검사하세요. `TelemetryHub` 자체는 동시 호출에 안전하지 않습니다.

## 관련 문서

[함수와 패키지](../../docs/authoring/functions-and-packages.md) ·
[생성물과 CI](../../docs/build-and-ship/generated-files-and-ci.md) ·
[예제 선택](../../docs/examples.md)
