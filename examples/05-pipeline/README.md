# 여러 기능을 조합한 Pipeline

상태를 가진 라이브러리에서 바인딩 기능을 함께 사용하는 예제입니다.

- opaque `Pipeline`이 복사한 UTF-8 이름과 retained Go 콜백을 소유합니다.
- enum·bool 상태, 입력 slice, typed error와 콜백 panic 처리를 조합합니다.
- `IntBatch`·`FloatBatch`는 generic 타입을 구체화해 등록합니다.
- `Close`, 수명 카운터와 동시 생성 테스트로 자원 정리를 확인합니다.
- `CompressionBound`는 zlib 링크 설정의 전파를 확인합니다.

## 실행

이 디렉터리에서 실행합니다.

```sh
zig build test go-check abi-check
zig build go
(cd go && go test -count=1 ./...)
(cd go && go test -run '^$' -bench BenchmarkPipelineProcess -benchmem ./pipeline)
```

먼저 `go-check`로 커밋된 생성물을 검사한 뒤 `go`로 갱신합니다.
선언 방법은 [바인딩 가이드](../../docs/bindings.md),
다른 예제는 [예제 선택 가이드](../../docs/examples.md)를 참고하세요.
