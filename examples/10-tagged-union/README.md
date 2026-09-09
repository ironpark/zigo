# Tagged union과 플러그인

Zig tagged union의 핸들 projection, 스냅샷과 Go 값 표현을 비교하고 JSON 및 enumkit 플러그인을
함께 사용하는 예제입니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다.
purego 테스트도 Zig로 빌드한 공유 라이브러리를 사용합니다. 로드 설정은 이 예제에 포함되어 있습니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

## 실행

```sh
zig build go go-doctor go-report
(cd go && go test ./...)

zig build go go-verify -Dpurego
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

이 예제는 다른 purego 예제의 별도 단계 대신 `-Dpurego` 옵션을 사용합니다.

## 예상 결과

cgo·purego 테스트가 통과하고 variant 접근, 스냅샷과 JSON 왕복을 검증합니다.
`go-report`는 최종 바인딩 계약을 출력합니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — union, packed 값과 열거형
- [src/bindings.zig](src/bindings.zig) — projection, 스냅샷, 값 union과 플러그인 옵션
- [빌드.zig](build.zig) — JSON·enumkit 플러그인 등록
- `go/tagged_union` — variant, 수명과 JSON 왕복 테스트

## 동작과 주의사항

| Zig 타입 | 표현 | 주요 Go API |
|---|---|---|
| `Value` | opaque 핸들 projection | `Tag`, `As<Variant>` |
| `Signal` | 핸들과 스냅샷 | `Snapshot`, projection 메서드 |
| `ScrollViewport` | 수명 없는 Go 값 | variant 생성자, `Tag`, `As<Variant>` |
| `RGB`, `Flags` | packed 값 | backing 변환과 필드 API |

JSON 플러그인은 열거형을 Zig 태그 문자열로, 값 타입을 정한 필드 이름으로 marshal합니다. enumkit은
`ModeValues()`와 `IsKnown()`을 추가합니다. 렌더링 플러그인은 Go 표면만 확장하며 C ABI를
바꾸지 않습니다. union variant 추가나 스냅샷 배치 변경은 ABI 변경이 될 수 있습니다.

## 관련 문서

[Tagged union](../../docs/authoring/tagged-unions.md) ·
[Plugin](../../docs/plugins/README.md) · [예제 선택](../../docs/examples.md)
