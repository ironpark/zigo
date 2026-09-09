# 지원 범위

이 문서는 zigo가 지원하는 toolchain, platform, ABI와 수명 제약의 정본입니다.

## toolchain과 platform

| 항목 | 지원 범위 |
|---|---|
| Zig | 0.16.0 |
| Go | 1.24 이상 |
| cgo 검증 platform | macOS·Linux amd64/arm64, Windows amd64 GNU ABI |
| purego | macOS·Linux·Windows amd64/arm64 |
| Windows cgo compiler | `CC="zig cc"` |
| purego module | `github.com/ebitengine/purego v0.10.2` |
| 미지원 | MSVC ABI, 32 bit target, mobile |

Go race detector는 cgo가 필요하므로 `CGO_ENABLED=0` purego test에서는 사용할 수 없습니다.

## cross compile

- reflection은 build host에서 실행하고 native library는 target용으로 빌드합니다.
- `c_long`처럼 host와 target에서 폭이 달라지는 타입 대신 고정 폭 타입을 사용합니다.
- target별 conditional public declaration은 target host에서도 생성·검증합니다.
- prebuilt archive는 `targets` mode에서 다른 target용으로 재빌드할 수 없습니다.
- foreign target에 대한 doctor load 검사는 실패가 아니라 `SKIP`일 수 있습니다.
- 최종 artifact는 반드시 target environment에서 실행합니다.

## 값과 ABI

- integer는 64 bit 이하, float는 `f32`와 `f64`를 지원합니다.
- `anyerror` 대신 명시적 error set을 사용합니다.
- generic function은 concrete specialization wrapper를 공개합니다.
- value struct는 적격 `extern struct` 또는 integer-backed `packed struct`입니다.
- nested pointer·slice result tree는 materialized 또는 handle로 표현합니다.
- 일반 slice element에 Go pointer가 포함될 수 없습니다.
- tagged union의 value, snapshot과 projection은 서로 다른 payload 제한을 가집니다.

전체 형태는 [타입 대응](type-mapping.md)을 확인하세요.

## memory와 lifetime

- Go string과 slice input은 호출 동안만 빌립니다.
- native가 input pointer를 보관해야 하면 Zig memory로 복사합니다.
- native-owned slice/string result는 Go로 복사한 뒤 등록한 release function으로 해제합니다.
- owned handle은 사용 후 명시적으로 `Close`합니다.
- borrowed handle과 union projection은 owner보다 오래 사용할 수 없습니다.
- dependent child를 닫기 전에 parent를 닫지 않습니다.
- finalizer cleanup은 실행 시점이나 process 종료 전 실행을 보장하지 않습니다.

## concurrency

생성 handle runtime은 method call과 `Close` 사이의 pointer lifetime을 보호합니다. Zig object의
여러 method를 자동으로 serialize하지는 않습니다. 원래 library가 thread-safe하지 않다면 Go
caller가 별도 lock을 사용합니다.

retained callback의 thread와 reentrancy option은 계약 정보입니다. arbitrary native thread에서
호출되는 callback이 접근하는 Go state는 application이 동기화합니다.

## panic과 복구

- error를 반환할 수 있는 boundary의 Zig panic은 `*NativePanicError`가 될 수 있습니다.
- error 결과가 없는 boundary의 panic은 process를 종료할 수 있습니다.
- Go callback panic은 boundary 밖에서 `*CallbackPanicError`로 다시 panic합니다.
- Zig panic에 참여한 handle은 poison되어 다시 사용할 수 없을 수 있습니다.
- poison handle의 destructor는 실행하지 않아 native allocation이 남을 수 있습니다.
- memory corruption과 hardware fault는 복구 대상으로 보지 않습니다.

## callback과 stream

- callback은 C calling convention function pointer여야 합니다.
- purego callback 결과는 `void`, `bool` 또는 `i32`입니다.
- stream과 cancel pointer는 호출 뒤까지 보관할 수 없습니다.
- stream은 optional, retained field 또는 callback payload로 지원하지 않습니다.
- cancellation은 Zig 코드가 flag를 읽는 cooperative 방식입니다.

## ABI compatibility

다음 변경은 독립 배포된 native consumer와 호환성을 깨뜨릴 수 있습니다.

- C symbol, prefix 또는 package 소유자 변경
- extern/packed struct layout 변경
- enum과 tagged-union value layout 변경
- optional, scalar width 또는 signedness 변경
- result ownership과 release function 변경
- callback signature, userdata 또는 retention 변경
- error tag code 재배치

호환성을 유지해야 하면 `abi_base`와 `zig build abi-check`를 사용하세요. 내부 C 표현은
[ABI 문서](../internals/abi.md)에서 설명합니다.
