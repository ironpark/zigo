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

```bash
cd examples/05-pipeline
zig build test
zig build go
zig build go-check abi-check
cd go && go test -count=1 ./...
```

## 문서 변경 확인

사용자 문서의 명령과 Zig 예제는 현재 `examples/`와 `build.zig`의 공개 옵션을 기준으로
유지한다. 내부 동작이나 지원 범위를 바꾸면 [사용자 위키](README.md)와
[설계 문서](../design/README.md)를 함께 갱신한다.
