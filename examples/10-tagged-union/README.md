# Tagged union과 plugin

Zig tagged union의 handle projection, snapshot과 Go 값 표현을 비교하고 JSON 및 enumkit plugin을
함께 사용하는 예제입니다.

## 실행

```sh
zig build test go-check abi-check
zig build go go-doctor go-report
(cd go && go test ./...)

zig build go go-verify -Dpurego
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

이 예제는 다른 purego 예제의 별도 step 대신 `-Dpurego` option을 사용합니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — union, packed 값과 enum
- [src/bindings.zig](src/bindings.zig) — projection, snapshot, 값 union과 plugin option
- [build.zig](build.zig) — JSON·enumkit plugin 등록
- `go/tagged_union` — variant, 수명과 JSON 왕복 테스트

## 생성되는 동작

| Zig type | 표현 | 주요 Go API |
|---|---|---|
| `Value` | opaque handle projection | `Tag`, `As<Variant>` |
| `Signal` | handle과 snapshot | `Snapshot`, projection method |
| `ScrollViewport` | 수명 없는 Go 값 | variant constructor, `Tag`, `As<Variant>` |
| `RGB`, `Flags` | packed 값 | backing 변환과 field API |

JSON plugin은 enum을 Zig tag 문자열로, 값 type을 정한 field 이름으로 marshal합니다. enumkit은
`ModeValues()`와 `IsKnown()`을 추가합니다. rendering plugin은 Go 표면만 확장하며 C ABI를
바꾸지 않습니다. union variant 추가나 snapshot layout 변경은 ABI 변경이 될 수 있습니다.

## 다음 문서

[Tagged union](../../docs/authoring/tagged-unions.md) ·
[Plugin](../../docs/plugins/README.md) · [예제 선택](../../docs/examples.md)
