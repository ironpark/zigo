# 첫 Zig → Rust 호출

[00-quick-start](../00-quick-start/README.md)의 Rust 버전입니다. 같은 Zig 함수를
Go 대신 Rust에서 호출합니다. C ABI shim과 C 헤더는 두 예제가 **바이트 단위로
같은 파일**을 씁니다 — 달라지는 것은 그 위에 얹히는 공개 패키지뿐입니다.

## 최소 백엔드입니다

Rust 백엔드는 세 가지 모양만 다룹니다: 스칼라, `[]const T` 슬라이스, error
union. 콜백·`std.Io` 스트림·tagged union·opaque handle·materialized 결과 트리·
취소는 범위 밖이며, 해당 선언을 바인딩하려 하면 `ZIGO060`으로 어떤 선언의 어떤
기능이 문제인지 이름을 대며 생성이 거부됩니다. 조용히 빠뜨리지 않습니다.

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
```

## 핵심 파일

1. [src/root.zig](src/root.zig) — 원래 Zig 함수 세 개
2. [src/bindings.zig](src/bindings.zig) — 노출할 함수 선택
3. [build.zig](build.zig) — `addRustBindings`로 모듈과 생성 단계 연결
4. [rust/Cargo.toml](rust/Cargo.toml)과 [rust/build.rs](rust/build.rs) — 직접
   작성하는 파일. Go 예제의 `go.mod`에 해당하며, `build.rs`가 정적 아카이브를
   링크합니다
5. [rust/src/lib.rs](rust/src/lib.rs) — 생성된 공개 API
6. [rust/src/raw.rs](rust/src/raw.rs) — 생성된 `extern "C"` 선언과 마셜링
7. [rust/src/error.rs](rust/src/error.rs) — `errors.lock.json`에서 생성된 오류 타입
8. [rust/examples/demo.rs](rust/examples/demo.rs)와
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
