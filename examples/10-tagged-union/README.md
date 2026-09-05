# Tagged union의 세 가지 표현

Zig tagged union을 handle projection, snapshot, 값 전달로 노출하는 예제입니다.
표현별 선언과 지원 payload는 [Tagged union 가이드](../../docs/bindings-unions.md)에 있습니다.

## 어떤 API가 생성되나요?

| 등록 타입 | 표현 | 주요 Go API |
|---|---|---|
| `Value` | opaque handle 뒤의 union | `Tag() (ValueTag, error)`, `As<Variant>() (payload, bool, error)` |
| `Signal` | handle에 snapshot 추가 | `Snapshot() (SignalSnapshot, error)`; projection도 유지 |
| `ScrollViewport` | 수명 관리가 없는 Go 값 | variant 생성자, `Tag()`, 값 인자·반환 |
| `RGB`, `Flags` | 직접 등록한 packed 값 | `Backing()`, `RGBFromBacking()` 등의 변환 |

이 예제는 `MustTag`, `MustAs<Variant>`, `MustSnapshot`도 생성합니다. 이 변형은
검사형 API의 오류를 panic으로 바꾸므로 정상적인 실패 처리가 필요하면 검사형을 쓰세요.

`Value` projection은 소유한 `*Value`와 borrowed `*ValueRef`에서 사용할 수 있습니다.
variant가 다르면 `bool`이 false이며, nil·닫힌 handle·무효한 부모는 native 호출 전에
오류로 거부합니다. payload가 없는 variant에는 tag 상수만 있고 payload accessor는 없습니다.

`Signal` snapshot은 tag와 scalar·bool·enum payload를 한 번의 native 호출로 가져옵니다.
이후 snapshot 읽기는 Go 값 접근입니다. snapshot union에 variant를 추가하면 레이아웃이
바뀌므로 ABI breaking 변경입니다.

`ScrollViewport`의 RGB payload는 `packed struct(u24)`, region payload는 평탄화한
scalar 필드로 전달합니다. slice를 담는 `unknown` variant는 `.omit_variants`로 제외하며,
native가 제외한 tag를 반환하면 Go 오류가 됩니다. 값 union의 variant 추가도 ABI를 바꿉니다.
`Flags`는 extern struct 필드, 평탄화한 필드, opaque accessor와 콜백의 packed 변환을 검증합니다.

## 실행

이 디렉터리에서 실행합니다. 이 예제의 purego 선택은 다른 예제의 `purego-go` 스텝과 달리
`-Dpurego` 옵션을 사용합니다.

```sh
zig build test go-check abi-check
zig build go go-doctor go-report
(cd go && go test ./...)

zig build go go-verify -Dpurego
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

테스트는 잘못된 variant, slice 복사, opaque 자식, 값 union의 왕복 변환과 수명 오류를
확인합니다. 같은 handle의 variant 변경과 접근을 공유할 때는 호출자가 동기화해야 합니다.
caller-owned handle의 GC 정리는 안전망이며 명시적인 `Close`를 대신하지 않습니다.

전체 예제 목록은 [예제 선택 가이드](../../docs/examples.md)를 참고하세요.
