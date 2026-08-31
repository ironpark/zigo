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
| tagged union | v2 자동 변환 | v1에 projection 기반 accessor로 구현됨 (03 §7) |
| 빌드 스텝 | 사용자가 `b.step`으로 직접 배선 | `addStandardSteps` 로 관용적 스텝 집합을 제공(직접 배선도 가능) |
| `Options` 필드 | `name`~`auto_cleanup` | `source_root`, `gofmt`, `go_package`, `backend`, `library_loading` 추가 |
| `GoBindings` 필드 | `update/check/abi_check/lib/semantic_json` | `report`, `doctor`, `install_library`, `library_filename` 추가 |
| generator 구조 | `gen/main.zig`, `gen/emit/*`, `gen/diff.zig` | `src/main.zig`, 단일 `gen/emit.zig`, `gen/abi_diff.zig`, 추가로 `cli.zig`, `generator.zig`, `report.zig`, `doctor.zig`, `sync_check.zig` |
| 함수 항목 문법 | `.{ .path = "root.version", ... }` | 명시 목록은 `.{ .name = "add", .@"fn" = lib.add }`. `.path` 는 `discover` 모드의 `overrides`/`exclude` 전용 |
| generic 구체화 | `.types` 안에 `.name` 항목 | 별도 `.specializations` 키 |
| Go 최소 버전 | 계획 문서의 "Go 1.26" | 생성 코드 요구는 Go 1.23+ (`auto_cleanup` 만 1.24+). CI가 1.26.x 로 검증 |

---

## 2. 미구현

| 항목 | 근거 문서 | 현재 상태 |
|---|---|---|
| `layout.<target>.json` 검증 | 02 §2 | reflector가 `pointer_bits`/`usize_bits`/`target` 만 채운 스텁을 쓰고 `structs` 는 항상 비어 있다. build.zig 는 이 파일을 소비하지 않는다(`_ = layout_json;`). 헤더 대조 검증은 없다 |
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
