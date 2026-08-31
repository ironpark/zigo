# 구현 상태

설계 문서(00~04)와 현재 저장소 구현을 대조한 기록이다. 세부 서술은 각 설계 문서 본문에
반영했고, 이 문서는 **설계와 어디가 다른지, 무엇이 아직 없는지**를 한 곳에서 보여준다.

기준: `docs/zig-go-binding-architecture` 브랜치의 `build.zig`, `src/`, `examples/`.

---

## 1. 설계와 달라진 것

| 항목 | 설계 문서의 서술 | 현재 구현 |
|---|---|---|
| purego 백엔드 | v2 이후 항목 | 구현됨. `.backend = .purego` + `.link_mode = .dynamic`, macOS/Linux × amd64/arm64 |
| 동적 링크 | "옵션만 예약" | 구현됨. 공유 라이브러리 산출 + 런타임 로딩 정책(`library_loading`) |
| tagged union | v1 거부, v2 "자동 변환" | v1에 projection 기반 accessor로 구현됨. opt-in 값 스냅샷 표현이 추가됨 (아래 §1.1, 03 §7, §7.1) |
| 빌드 스텝 | 사용자가 `b.step`으로 직접 배선 | `addStandardSteps` 로 관용적 스텝 집합을 제공(직접 배선도 가능) |
| `Options` 필드 | `name`~`auto_cleanup` | `source_root`, `gofmt`, `go_package`, `backend`, `library_loading` 추가 |
| `GoBindings` 필드 | `update/check/abi_check/lib/semantic_json` | `report`, `doctor`, `install_library`, `library_filename` 추가 |
| generator 구조 | `gen/main.zig`, `gen/emit/*`, `gen/diff.zig` | `src/main.zig`, 단일 `gen/emit.zig`, `gen/abi_diff.zig`, 추가로 `cli.zig`, `generator.zig`, `report.zig`, `doctor.zig`, `sync_check.zig` |
| 함수 항목 문법 | `.{ .path = "root.version", ... }` | 초안대로 돌아왔다. `.functions` 는 두 모드에서 같은 경로 문법을 쓰고 `.@"fn"` 은 없다 |
| generic 구체화 | `.types` 안에 `.name` 항목 | 초안대로 돌아왔다. 별도 `.specializations` 키는 없앴다 |
| Go 최소 버전 | 계획 문서의 "Go 1.26" | 생성 코드 요구는 Go 1.23+ (`auto_cleanup` 만 1.24+). CI가 1.26.x 로 검증 |

### 1.1 tagged union — 초안과 구현의 차이

초안은 tagged union에 **설계를 두지 않았다.** `ZIGO006`을 "tagged union (v1) — 표현 미정"으로
정의해 어떤 형태로든 노출을 거부했고, 01 §12의 비범위 목록에 "tagged union 자동 변환 — v2"
한 줄만 남겼다. 즉 v2에 무엇을 만들지에 대한 합의가 아니라 **판단 보류**였다.

구현은 그 보류를 다음 결정들로 채웠다.

| 쟁점 | 초안 | 구현 |
|---|---|---|
| C 표현 | 미정 (값 전달 시 layout 노출이 필요해 보류) | union layout을 C로 복제하지 않는다. opaque handle 포인터로만 노출 |
| 접근 방식 | 미정 | variant마다 projection 심볼 (`zg_value_project_<variant>`) |
| 실패 표현 | 미정 | projection 반환값 4상태: `0` mismatch, `1` success, `2` invalid handle/output, `3` Zig panic |
| Go API | "자동 변환" | 확인형 `TryTag()`/`TryAs*()` 와 typed error로 panic하는 편의형 `Tag()`/`As*()` 이중 표면 |
| payload 범위 | 미정 | 스칼라·enum·numeric slice(Go 소유로 복사)·opaque handle(부모에 종속된 borrowed `TRef`) |
| `ZIGO006` | tagged union 전부 거부 | by-value 전달과 내릴 수 없는 payload만 거부 |
| ABI 규칙 | 없음 | tag 값과 순서를 보존한 끝부분 variant 추가는 compatible append, 그 외 변경은 breaking |

핵심 차이는 "자동 변환"이라는 표현이 암시하던 **Zig 배치의 값 기반 미러링을 하지
않는다**는 점이다. union의 메모리 배치는 Zig 명세상 보장되지 않으므로(00 §3과 같은 이유)
배치를 노출하는 대신 tag 검사를 거친 projection만 노출한다. 그 결과 Go 쪽에는 "잘못된
variant 접근"이라는 상태가 항상 존재하고, 초안에 없던 `TryAs*` 계열 API가 필요해졌다.

projection의 대가는 접근 한 번마다 FFI 왕복이다. 이를 줄이기 위해 `.repr =
.tagged_union, .access = .snapshot`이 뒤이어 추가되었다(03 §7.1). 이것도 Zig 배치를 복제하지 않는다.
zigo가 자기 소유의 `extern struct`를 정의하고 shim이 값을 옮겨 담아, tag와 payload를 한 번의
호출로 함께 넘긴다. 기본값은 그대로 projection이고, 값 스냅샷은 payload가 전부
void/bool/스칼라/enum인 union이 명시적으로 opt-in할 때만 생성된다. 대신 variant 추가가 구조체
배치를 바꾸므로 ABI 판정이 projection과 반대로 breaking이 된다.

### 1.2 extern struct 값 파라미터 — 문서와 구현의 차이

00 §3과 03 §6은 "값 전달을 원하면 `extern struct`로 선언하라"고 안내했지만 그 경로는
구현되어 있지 않았다. `value_struct`가 semantic IR, validate, abi_diff, report에는 있고
lower와 emit에는 없어서, 등록한 struct를 파라미터로 쓰면 `lower.zig`의 `else =>
unreachable`에서 generator가 패닉했다. 문서가 권장하는 경로가 도달 가능한 unreachable이었다.

구현은 그 경로를 열되 "값 전달"이라는 서술을 고쳤다. **zigo는 어떤 aggregate도 C 경계를
값으로 넘기지 않는다.** `extern struct`는 in이면 `const T*`, out이면 `T*`로 내려가고 값
의미는 생성된 Go 코드가 유지한다. 플랫폼별 aggregate 전달 규칙과 purego의 스칼라·포인터
전용 raw 시그니처를 모두 피하기 위해서이며, tagged union 값 스냅샷(§1.1)이 out 포인터를
쓰는 것과 같은 판단이다. 적격 조건은 `ZIGO012`와 `ZIGO013`이 지키고, `packed struct`의
정수 백킹 노출은 비범위로 두어 `ZIGO003`이 거부한다.

---

## 2. 미구현

| 항목 | 근거 문서 | 현재 상태 |
|---|---|---|
| 헤더 레이아웃 대조 검증 | 00 §7 | 없다. 한때 `layout.<target>.json` 스텁이 있었으나 `structs` 가 항상 비어 있고 어떤 스텝도 읽지 않아 제거했다. 정확성은 `extern struct` 제한(00 §3)과 shim의 comptime 단언(03 §6.1)이 유지한다. 타깃별 레이아웃을 컴파일 산출물에서 뽑아 헤더와 대조하는 검증은 후속 과제다 |
| 크로스 컴파일 | 00 §7 | 미지원. reflector 실행 제약 그대로 |
| Windows·모바일·purego Tier 2 타깃 | — | 미지원 |
| Go 외 언어 | 01 §12 | 비범위 유지 |

---

## 3. 유지되는 설계 원칙

다음은 문서와 구현이 일치한다. 변경 시 되돌아볼 불변식이다.

- Zig 소스는 타입 판단에 파싱하지 않는다. AST는 파라미터 이름과 doc comment에만 쓴다.
- 일반 `struct` 는 값 전달하지 않는다. `extern`/`packed` 만 값으로 내린다.
- 에러 코드는 `errors.lock.json` 의 append-only 매핑이며 `@intFromError` 를 쓰지 않는다.
- 하강 규칙은 `lower` 단계에서 끝나고 세 emitter는 같은 `AbiFn` 만 읽는다.
- 애매하면 산출물을 내지 않고 진단으로 실패한다.
