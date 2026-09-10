# 첫 Zig → Rust 호출

[00-quick-start](../00-quick-start/README.md)의 Rust 버전입니다. 같은 Zig 함수를
Go 대신 Rust에서 호출합니다. C ABI shim과 C 헤더는 두 예제가 **바이트 단위로
같은 파일**을 씁니다 — 달라지는 것은 그 위에 얹히는 공개 패키지뿐입니다.

## 다루는 범위

Rust 백엔드가 다루는 모양입니다.

| Zig | Rust |
|---|---|
| 스칼라 | 같은 폭의 스칼라 |
| `[]const T` 파라미터 | `&[T]`, UTF-8이면 `&str` |
| error union | `Result<T, Error>` |
| `opaque` 핸들 | `Drop`으로 스스로 해제하는 구조체 |
| `*T` 수신자 / 값 수신자 | `&mut self` / `&self` |
| 빌려온 view | 라이프타임이 붙은 래퍼, `Drop` 없음 |
| 호출자 소유 버퍼 | `OwnedSlice<T>`, 복사 없음 |

범위 밖: 콜백, `std.Io` 스트림, tagged union, 등록된 enum, Zig 네임스페이스,
sub-package, materialized 결과 트리, 취소, 동적 로딩. 해당 선언을 바인딩하려
하면 `ZIGO060`으로 **어떤 선언의 어떤 기능이 문제인지 이름을 대며** 생성이
거부됩니다. 조용히 빠뜨리거나 다른 것으로 바꿔치지 않습니다 — 예를 들어
등록된 enum을 tag 정수로 넘기는 것은 컴파일은 되지만 호출자가 `0`이 무엇인지
알 방법이 없어서, 거부하는 쪽이 낫다고 판단했습니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0과 Rust
툴체인(`cargo`, `rustc`, `rustfmt`)이 필요합니다. Go는 필요하지 않습니다.

## 실행

```sh
zig build rust
(cd rust && cargo run --example demo)
(cd rust && cargo test)
```

## 예상 결과

데모가 다음을 출력하고 `cargo test`가 통과합니다.

```
2 + 3 = 5
sum([1, 2, 3]) = 6
7 / 2 = 3
1 / 0 failed: zigo: divide: DivideByZero
tally.add(40) = 40
tally.add(2) = 42
tally.peek() = 42
reading.total() = 42
tally.render() = total=42
live bytes after drop = 0
```

마지막 줄이 중요합니다. `Drop`이 실제로 네이티브 destructor에 도달했다는 증거는
라이브러리가 스스로 세는 바이트 수가 0으로 돌아오는 것뿐입니다. 코드 어디에도
`close`나 `deinit` 호출은 없습니다.

## 핵심 파일

1. [src/root.zig](src/root.zig) — 원래 Zig 함수 세 개
2. [src/bindings.zig](src/bindings.zig) — 노출할 함수 선택
3. [build.zig](build.zig) — `addRustBindings`로 모듈과 생성 단계 연결
4. [rust/Cargo.toml](rust/Cargo.toml)과 [rust/build.rs](rust/build.rs) — 직접
   작성하는 파일. Go 예제의 `go.mod`에 해당하며, `build.rs`가 정적 아카이브를
   링크합니다
5. [rust/src/lib.rs](rust/src/lib.rs) — 생성된 공개 API (자유 함수)
6. [rust/src/handle.rs](rust/src/handle.rs) — 생성된 핸들과 view 타입
7. [rust/src/buffer.rs](rust/src/buffer.rs) — 생성된 `OwnedSlice<T>`
8. [rust/src/raw.rs](rust/src/raw.rs) — 생성된 `extern "C"` 선언과 마셜링
9. [rust/src/error.rs](rust/src/error.rs) — `errors.lock.json`에서 생성된 오류 타입
10. [rust/examples/demo.rs](rust/examples/demo.rs)와
    [rust/tests/bindings.rs](rust/tests/bindings.rs) — 호출하는 쪽

## 빌드 단계

| 단계 | 하는 일 |
|---|---|
| `zig build test` | Zig 쪽 단위 테스트 |
| `zig build rust` | 크레이트 소스 생성·포맷, 네이티브 라이브러리와 헤더 설치 |
| `zig build rust-check` | 커밋된 크레이트가 낡았으면 실패 |
| `zig build rust-lib` | 네이티브 라이브러리만 빌드·설치 |
| `zig build rust-coverage` | 공개 Zig API 바인딩 커버리지 |
| `zig build abi-check` | `HEAD` 대비 파괴적 ABI 변경이면 실패 |

`cargo test`는 `zig build`에서 돌리지 않습니다. `cargo`는 의존성을 해석하며
네트워크에 접근할 수 있어 빌드 단계로 삼기에 적절하지 않습니다. Go 예제가
`go test`를 별도로 실행하는 것과 같은 이유입니다.

## Rust 쪽이 더 자연스러운 지점

- **error union → `Result<T, E>`**: Go는 `(T, error)`를 돌려주므로 생성된 본문이
  실패했을 때 `T`에 무엇을 담을지 정해야 합니다. Rust에서는 payload가 없는
  상태를 표현할 수 없으니 정할 것이 없습니다.
- **핸들 → `Drop`**: Go 바인딩은 `Close()`를 공개하고, 모든 메서드가 "이미
  닫혔는지"를 런타임에 검사하고, 네이티브 panic이 새면 핸들을 poison합니다.
  닫힌 핸들도 여전히 쓸 수 있는 Go 값이기 때문입니다. Rust 래퍼는 자기 수명
  동안만 포인터를 소유하므로 잊을 `Close`도, 검사할 use-after-close도 없습니다.
  생성된 `handle.rs`에는 `close`도 `is_closed`도 유효성 플래그도 없습니다.
- **Zig 에러 집합이 없는 메서드는 값을 돌려줍니다**: 핸들 메서드는 C ABI에서
  무조건 상태 코드를 갖습니다(네이티브 panic을 보고할 통로가 필요해서). 그래서
  Go는 `add`조차 `(int64, error)`입니다. Rust에서 도달 가능한 0 아닌 코드는
  잘못된 핸들(`Drop`이 소유하므로 도달 불가)과 잡힌 Zig panic(라이브러리 결함)
  뿐이므로, 값을 돌려주고 결함이면 panic합니다. Zig에서 에러 집합을 선언한
  메서드만 `Result`입니다.
- **수신자의 가변성**: `*Tally`는 `&mut self`, 값 수신자는 `&self`가 됩니다.
  Go는 모든 수신자가 `*Tally`라 이 구분을 아예 표현하지 못합니다.
- **빌려온 view → 라이프타임**: Go는 "부모 핸들이 열려 있는 동안만 유효하다"를
  주석으로 적고 런타임에 검사합니다. Rust는 컴파일 오류로 만듭니다. 이 주장은
  `rust_borrowed_view` generator case의 `compile_fail.rs`가 실제로
  `E0515`를 내는지 빌드가 확인합니다.
- **호출자 소유 버퍼 → 복사 없음**: Go의 GC는 Zig 포인터를 소유할 수 없어
  payload를 복사하고 반환 전에 release를 호출합니다(호출당 할당 1회 + 전체 복사
  1회). Rust는 `OwnedSlice<T>`가 할당을 직접 소유하고 `Drop`에서 해제합니다.
  release 함수는 **공개하지 않습니다** — 이미 스스로 해제하는 값 옆에 두면
  이중 해제를 부르기 때문입니다. Go는 둘 다 공개하고 주석으로 경고합니다.
- **빈 슬라이스**: Rust의 빈 슬라이스도 null이 아닌 정렬된 포인터를 돌려주는데,
  이는 Zig `[]const T`가 요구하는 것과 정확히 같습니다. Go 쪽 `zigoZeroSlot`에
  해당하는 장치가 필요하지 않습니다.

## 동작과 주의사항

`rust/src/*.rs`는 생성물이므로 직접 수정하지 않습니다. 테스트를
`rust/tests/`에 두는 것도 그래서입니다 — `src/lib.rs` 안의 `#[cfg(test)]`
모듈은 다음 `zig build rust`에서 덮어써집니다.

`build.rs`가 `../zig-out/lib`에서 아카이브를 찾으므로, `cargo` 전에 한 번은
`zig build rust`(또는 `rust-lib`)를 실행해야 합니다.

## 관련 문서

[00-quick-start](../00-quick-start/README.md) · [오류 예제](../02-errors/README.md) ·
[예제 선택](../../docs/examples.md)
