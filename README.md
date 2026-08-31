# zigo

zigo는 Zig 라이브러리의 공개 API를 관측해 Go 바인딩을 생성한다. Zig의 comptime
reflection 결과를 바탕으로 C ABI shim, C 헤더, cgo 코드와 Go API를 함께 만든다.

> 상태: v1 구현 완료. Zig 0.16.0과 Go 1.23 이상에서 네이티브 macOS/Linux 빌드를 지원한다.

## 주요 기능

- Zig 라이브러리 소스를 수정하지 않고 `bindings.zig`에서 노출할 API를 선언한다.
- 스칼라, 슬라이스, 에러 유니온, opaque 타입, tagged-union accessor, generic specialization과 콜백을 지원한다.
- Go용 raw 계층과 public 계층, C 헤더와 Zig shim을 한 번에 생성한다.
- `go-check`로 생성물 동기화를 검사하고, 필요하면 `abi-check`를 켜 호환성 파괴를 막는다.
- opt-in purego 백엔드로 공유 라이브러리를 런타임에 로드해 `CGO_ENABLED=0` Go 빌드를 지원한다.

## 빠른 시작

```bash
zig fetch --save git+https://github.com/ironpark/zigo
```

```zig
// build.zig
const bindings = zigo.addGoBindings(b, .{
    .name = "mylib",
    .module = mylib,                          // b.addModule로 만든 대상 모듈
    .bindings = b.path("src/bindings.zig"),
    .source_root = b.path("src/root.zig"),
    .go_dir = b.path("go"),
    .go_module = "example.com/mylib/go",
    .target = target,
    .optimize = optimize,
});
_ = bindings.addStandardSteps(b, .{});
```

```zig
// src/bindings.zig — Go에 노출할 선언만 적는다
const zigo = @import("zigo");
const mylib = @import("mylib");

pub const bindings = zigo.define(.{
    .root = mylib,
    .discover = .public,
});
```

```bash
zig build go              # 바인딩 생성 + 네이티브 라이브러리 설치
cd go && go test ./...
```

생성된 Go 소스와 `zigo/` 메타데이터는 저장소에 함께 커밋한다. 전체 절차와 CI 배선은
[설치와 사용](docs/getting-started.md)에 있다.

C 컴파일러 없이 Go를 빌드해야 하면 purego 백엔드를 추가로 등록한다. 공개 Go API는
그대로이고 네이티브 공유 라이브러리를 실행 시점에 로드한다 →
[공유 라이브러리와 purego 백엔드](docs/purego.md).

## 문서

[사용자 문서 목차](docs/README.md)에서 시작한다.

- [설치와 사용](docs/getting-started.md) — 의존성 추가부터 CI 게이트까지의 절차
- [설정과 생성물](docs/configuration.md) — `addGoBindings` 옵션과 선언 메타데이터
- [예제](docs/examples.md) — 예제 10종이 각각 다루는 범위
- [제한사항](docs/limitations.md) — 지원 범위와 FFI 계약
- [설계 문서](docs/.agent/design/README.md) — 내부 아키텍처와 설계 근거
