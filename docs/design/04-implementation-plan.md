# 구현 계획

전제: Zig 0.16.0, Go 1.26. 현재 저장소는 `zig init` 스캐폴드 (`src/root.zig`, `src/main.zig`).

배포 형태: **Zig 패키지 의존성.** 사용자 진입점은 `zigo.addGoBindings(b, .{...})` 하나다.

목표 순서: **얇은 수직 슬라이스를 먼저 끝까지 관통시킨 뒤 폭을 넓힌다.**
컴포넌트를 각각 완성하고 마지막에 잇는 방식은 통합 시점에 설계 오류가 한꺼번에 드러난다.

---

## 마일스톤 개요

| # | 이름 | 완료 기준 |
|---|---|---|
| M0 | 골격 + 빌드 API 뼈대 | 예제 저장소가 zigo를 의존성으로 fetch하고 `zig build go`가 (빈) 스텝을 실행 |
| M1 | **수직 슬라이스** | 예제에서 `mylib.Add(3,7)==10` 이 Go 테스트로 통과 |
| M2 | 에러 & 슬라이스 | `errors.Is(err, mylib.ErrDivideByZero)` 성립 |
| M3 | opaque 타입 | `New*`/`Close` 왕복 후 할당 카운터 0 |
| M4 | 이름 & 메타데이터 | `[]const u8 + utf8_string` → Go `string` 왕복 |
| M5 | 검증 & 진단 | 하강 실패 9종 전부 스냅샷 테스트 |
| M6 | 소스 동기화 & ABI diff | `zig build go-check abi-check`가 CI 게이트로 동작 |
| M7 | generic & 콜백 | Go 콜백 panic이 프로세스를 죽이지 않음 |
| M8 | 마감 | 예제 저장소 CI 그린, 문서화 |

---

## M0 — 골격 + 빌드 API 뼈대

```text
build.zig               # ★ 이 파일이 zigo의 공개 API다
src/
  build_api.zig         # addGoBindings 구현 (build.zig에서 re-export)
  root.zig              # 모듈 "zigo": zigo.define DSL
  reflect/
    main.zig            # reflector root. @import("bindings")
    walk.zig            # comptime 타입 그래프 순회
    json_out.zig
  gen/
    main.zig            # zigo-gen exe 진입 (generate / check / abi-diff)
    ir/
      semantic.zig  abi.zig  errors_lock.zig
    validate.zig
    lower.zig
    emit/
      emitter.zig  zig_shim.zig  c_header.zig  go_raw.zig  go_public.zig  naming.zig
    diff.zig
examples/
  01-scalar/ 02-errors/ 03-opaque/ 04-callback/     # 각각 독립 Zig+Go 프로젝트
tests/
  fixtures/   # IR 입력
  snapshots/  # 기대 산출물
```

작업:
1. **`build.zig` 재작성.** 현 스캐폴드의 run/test 스텝을 걷어내고:
   - `b.addModule("zigo", ...)` — 사용자 `bindings.zig`가 쓸 DSL 모듈
   - `zigo-gen` 실행 파일 (사용자 그래프에서 `b.addRunArtifact`로 소비됨)
   - `pub fn addGoBindings(b, opts) GoBindings` re-export
   - `test` 스텝
2. `Options` / `GoBindings` 구조체 확정 (`01-architecture.md` §5)
3. 진단 타입: `{ severity, code, message, zig_decl, hint }`
4. 스냅샷 하네스 — 디렉터리 트리 비교 + `--update-snapshots`

**테스트 하네스를 M0에 넣는 이유:** 코드 생성기는 골든 파일 테스트가 없으면
리팩터링이 불가능해진다. 첫날에 만든다.

**완료 기준:** `examples/01-scalar`가 `.dependencies.zigo = .{ .path = "../.." }` 로
zigo를 참조하고, `zig build go`가 (아직 아무것도 안 하지만) 성공한다.

> **주의:** `addGoBindings`는 사용자에게 노출되는 유일한 표면이다.
> 여기서 잘못 잡은 시그니처는 나중에 모든 사용자의 build.zig를 깨뜨린다.
> M0에서 시간을 더 쓰더라도 옵션 구조체를 신중히 결정할 것.

---

## M1 — 수직 슬라이스 (가장 중요)

목표: `examples/01-scalar`의
```zig
pub fn add(a: i32, b: i32) i32
```
가 Go에서 `mylib.Add(3, 7) == 10` 으로 호출되기까지 **전 단계를 관통**한다.

작업:
1. `zigo.define` 최소 DSL (`.functions` 만)
2. **모듈 배선으로 reflector 구성** — 소스 문자열 합성 없음:
   ```zig
   const bindings_mod = b.createModule(.{
       .root_source_file = opts.bindings,
       .imports = &.{ .{"zigo", zigo_mod}, .{opts.name, opts.module} },
   });
   const reflector = b.addExecutable(.{ .root_module = b.createModule(.{
       .root_source_file = b.path("src/reflect/main.zig"),
       .imports = &.{ .{ .name = "bindings", .module = bindings_mod } },
   })});
   const ir = b.addRunArtifact(reflector).captureStdOut();
   ```
3. semantic IR: 스칼라 + 자유 함수만
4. lower: 항등 변환
5. emit 4종 (shim / header / raw / public) — 스칼라만
6. `b.addLibrary(.{ .linkage = .static })` 로 shim + 사용자 모듈 → `.a`, `installArtifact`
7. `UpdateSourceFiles`로 Go 파일을 `go_dir`에 기록
8. cgo 지시자 경로 계산 (`${SRCDIR}` 상대)
9. `cd examples/01-scalar/go && go test ./...` 통과

**여기서 검증되는 가설:** 모듈 배선 → comptime reflection → JSON → 코드 생성 →
소스 트리 기록 → cgo 링크의 전체 경로가 실제로 동작하는가.
이 마일스톤이 실패하면 아키텍처를 재검토한다.

**M1에서 확정해야 할 미지수:**
- `captureStdOut()`으로 받은 LazyPath를 generator 인자로 넘기는 배선
- generator 출력 디렉터리(`addOutputDirectoryArg`) → `UpdateSourceFiles` 연결
- install prefix가 확정되기 전에 cgo 경로를 계산하는 방법
  (해법: `b.install_prefix`가 아니라 `${SRCDIR}` 상대 고정 규약 사용)

---

## M2 — 에러 유니온 & 슬라이스

작업:
1. `errors_lock.zig` — append-only 테이블, 기존 매핑 변경 시도 거부
2. `anyerror` 반환 거부 진단
3. error union 하강: 안정 코드 반환 + payload out 파라미터
4. `[]const T` / `[]T` → ptr+len(+written) 분해
5. Go 에러 타입 생성 (`Error`, `ErrXxx` 센티널, `errors.Is` 지원)
6. Go 포인터 규칙 검증 — 원소에 포인터 포함 시 거부

예제 `02-errors`:
```zig
pub fn divide(a: i32, b: i32) error{DivideByZero}!i32
pub fn sum(values: []const f64) f64
```

**완료 기준:** `errors.Is(err, mylib.ErrDivideByZero)` 성립.
`errors.lock.json`을 재생성해도 코드 값이 변하지 않음.

---

## M3 — opaque 타입 & 생명주기

작업:
1. `.types = .{ .{ .type = X, .repr = .@"opaque" } }`
2. init/deinit 짝 탐색 (`init|create|new|open` ↔ `deinit|destroy|close`)
3. 메서드 하강 — `receiver` 필드, `self: *T` 첫 파라미터 제거
4. Go: `New*() (*T, error)`, `Close()` (`sync.Once` 멱등), `TRef` (borrowed)
5. 일반 struct 값 전달 시도 → 진단 후 거부

예제 `03-opaque`: `Context.init/process/deinit`

**완료 기준:** 반복 생성/해제 후 Zig 쪽 할당 카운터 0 (테스트용 카운팅 allocator).

---

## M4 — 파라미터 이름 & 메타데이터

3단계 이름 해석:

1. **사이드카** — `.params = .{ "input", "output" }` (권위)
2. **AST 추출** — `std.zig.Ast`로 원본을 파싱해 파라미터 이름 + doc comment 수집.
   *문법 수준만* 사용하며 타입 판단에는 절대 쓰지 않는다. 매칭 실패는 조용히 폴백.
3. **폴백** — `p0, p1, …` + 경고

동시에 `semantic`(utf8_string / c_string / opaque_bytes), `retention`, `direction`을
DSL에 추가하고 하강에 반영.

**AST 경로의 난점:** 빌드 시스템 안에서 원본 `.zig` 파일 경로를 알아야 한다.
`opts.module.root_source_file`로 루트는 알 수 있지만 `@import`된 하위 파일은 추적이 필요하다.
v1은 **루트 파일과 `bindings.zig`가 직접 참조하는 파일까지만** 스캔한다.

**완료 기준:** `[]const u8 + utf8_string` → Go `string` 왕복 테스트 통과.

**주의:** AST 추출은 "있으면 좋은" 기능이다. 복잡도가 예상을 넘으면 잘라내고
사이드카만으로 진행한다 — 기능적으로 충분하다.

---

## M5 — 검증 & 진단 완성

`03-lowering-rules.md` §10의 9가지 실패 케이스 각각에:
진단 코드(`ZIGO001`…) + 수정 방법 + 스냅샷 테스트 1개.

```
error[ZIGO003]: cannot pass `mylib.Config` by value
  --> src/bindings.zig: functions[2] (mylib.configure)
  Zig struct layout is unspecified for non-extern structs.
  hint: declare it as `extern struct`, or expose it as
        .{ .type = mylib.Config, .repr = .@"opaque" }
```

진단은 generator가 stderr로 내고 0이 아닌 코드로 종료한다.
빌드 시스템이 이를 스텝 실패로 표면화한다.

**완료 기준:** 잘못된 입력에서 절대 산출물을 내지 않고 진단만 낸다.

---

## M6 — 소스 동기화 & ABI diff

**(a) `go-check`**
동일 생성을 수행하되 기록 대신 `go_dir`과 비교한다. 다르면 어떤 파일이 다른지 출력하고 실패.
생성물 커밋을 강제하는 CI 게이트.

**(b) ABI diff**
1. `semantic.json` 정규화 직렬화 (키 정렬) — diff 잡음 제거의 전제
2. `zigo-gen abi-diff --base <old.json> --current <new.json>`: 두 semantic 문서 파싱
3. 판정기: BREAKING / ADDED / ABI COMPATIBLE
4. `--fail-on breaking` 종료 코드, `--json` 출력
5. `abi_check` 스텝으로 노출

**완료 기준:** 파라미터 타입 변경 시 BREAKING, 함수 추가 시 ADDED 검출.
`zig build go-check abi-check` 가 예제 저장소 CI에서 동작.

---

## M7 — generic specialization & 콜백

**generic:**
1. `.{ .name = "FloatBuffer", .type = lib.Buffer(f32) }` 처리
2. reflector가 이미 구체화된 타입만 보므로 추가 로직은 거의 없다 — **주로 이름 배정 문제**
3. comptime 파라미터가 남은 함수는 거부 (ZIGO008)

**콜백:**
1. `callconv(.c)` 검증
2. C 트램폴린 + `cgo.NewHandle` 생성
3. 트램폴린 내부 `defer recover()` → `-3 CallbackPanic`
4. `retained` 콜백의 Handle 수명 관리 + `Close()` 강제 생성

예제 `04-callback`

**완료 기준:** Go 콜백에서 panic이 나도 프로세스가 죽지 않고 에러 코드가 반환된다.

---

## M8 — 마감

1. shim에 panic 핸들러 설치 → `-2 PanicCaught` + `zg_last_error_message()`
2. `linkSystemLibrary` 관측 → `#cgo LDFLAGS` 반영 (`-framework`, `-lm` 등)
3. `go.mod` 부트스트랩 (없을 때만 1회 생성, 이후 사용자 소유)
4. 예제 4종 CI 워크플로 (macOS/Linux)
5. cgo 호출 오버헤드 벤치마크를 CI에 기록 (회귀 감지)
6. README / 예제 문서화

**v1 종료.**

---

## v2 이후

- 크로스 컴파일 — 레이아웃 상수를 타깃별 컴파일 산출물에서 추출
- 동적 링크 배포 시나리오 (`link_mode = .dynamic`)
- tagged union 변환
- `purego`/dlopen 백엔드 (cgo 없는 빌드)
- 배치 API 힌트로 cgo 오버헤드 완화

---

## 검증 방법

| 층 | 방법 |
|---|---|
| reflector | JSON 골든 파일 — Zig 버전 업그레이드 감지기 역할 |
| validate/lower | IR 픽스처 → IR 골든 + 실패 케이스 스냅샷 |
| emitter | 생성 코드 골든 파일 |
| 빌드 API | 예제 4종이 실제 의존성으로 zigo를 fetch해 빌드 |
| 통합 | 예제 4종의 `go test` |
| 메모리 | 카운팅 allocator로 누수 0 검증 |
| 성능 | cgo 호출 벤치마크 CI 기록 |

generator가 순수 함수(IR in → 파일 out)인 덕분에 위 3개 층은
실제 Zig 프로젝트 없이 테스트된다. 이것이 reflector와 generator를 분리한 주된 이유다.

---

## 즉시 착수 순서

1. **`build.zig`를 zigo의 공개 API로 재작성** — `addGoBindings` 시그니처 확정
2. `examples/01-scalar/` 를 `.path = "../.."` 의존성으로 세팅 (API를 즉시 사용해보기)
3. `src/gen/ir/semantic.zig` — IR을 문서가 아니라 **Zig 타입으로 고정**
4. `src/reflect/` 로 스칼라 함수만 관측
5. M1 관통

1번과 2번을 함께 하는 것이 중요하다. 공개 빌드 API는 실제 소비자 없이 설계하면
거의 반드시 틀린다. 예제를 첫 사용자로 두고 API를 역으로 다듬는다.
