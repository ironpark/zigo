# Zig 테스트 커버리지 감사

최종 검증 기준: 2026-08-30, Zig 0.16.0. 보강 후 `zig build test --summary all`은
31/31 build step과 64/64 test를 통과했다. 아래 항목은 최초 감사에서 발견한 공백과
이번 보강의 처리 상태를 함께 기록한다.

이 감사에서 커버리지는 line percentage가 아니라 production 계약을 증명하는 테스트의 형태로
판정한다. 직접 unit test, generator golden, 소비자 예제 compile, Go runtime test는 서로 다른
근거이며 하나가 다른 하나를 완전히 대체하지 않는다.

## 실제 discovery

루트 `test` step에서 실행되는 64개 테스트의 분포는 다음과 같다.

| Test artifact | 테스트 수 | 주된 범위 |
|---|---:|---|
| root aggregate | 9 | `define`, semantic parser/round trip/OOM, errors lock 연동, snapshot |
| generator | 19 | generator, validator, lowering, naming |
| reflect walk | 5 | reflection, generic specialization, automatic discovery |
| reflect names | 6 | AST 이름·문서 보강과 파일 실패 |
| ABI diff | 6 | breaking/compatible 분류와 OOM |
| errors lock | 5 | parse, append-only, remap과 예약 코드 |
| diagnostic | 2 | rendering과 OOM |
| sync check | 3 | changed/obsolete 파일과 OOM |
| CLI parser | 5 | named argument, defaults, parse diagnostics |
| build options | 4 | raw package path component와 Go identifier/keyword |

두 generator golden case와 6개 CLI/process contract는 별도 process step으로 실행되며 위
64개에는 포함되지 않는다. process contract는 help, parse error, invalid semantic, stale 생성물,
breaking ABI와 실제 invalid consumer project의 exit/output을 캡처해 검사한다.

9개 example root의 Zig test 16개는 모두 표준 `test` step으로 실행되며 CI example loop에도
연결됐다.

## 최초 감사 항목과 조치 상태

각 번호의 제목과 상세 관찰은 최초 감사 시점을 보존하며, 바로 아래의 상태 문단이 현재
결론이다.

### P0 — 즉시 보강

1. **Example Zig 테스트가 CI에서 실행되지 않는다.**

   **해결.** 모든 예제에 `test` step을 추가하고 CI loop에서 실행한다.

   14개 테스트에는 allocator 회수, typed error, callback 상태, queue transaction과 telemetry
   lifecycle 검증이 들어 있다. 모든 example에 동일한 `test` step을 제공하고 CI loop에서
   `zig build test --summary all`을 실행해야 한다.

2. **Semantic 참조 무결성 실패가 오류가 아니라 generator panic이 된다.**

   **해결.** `ZIGO010`이 type uniqueness, enum tag, 참조 종류, receiver와 constructor 계약을
   lowering 전에 검사한다. 과거 exit 134 입력은 이제 진단을 출력하고 exit 1로 끝난다.

   validator는 enum node가 가리키는 type declaration의 존재와 `tag_type`을 검사하지 않는다.
   임시 semantic에서 parameter를 존재하지 않는 `MissingMode` enum으로 지정했을 때 generator는
   `lower.zig:148`의 `unreachable`에 도달해 exit 134로 종료됐다. 이 경로는 현재 Zig 테스트에
   없다.

   우선 unknown enum ref, enum without integer tag, unknown opaque/value type, duplicate type name,
   잘못된 constructor type/init/deinit을 table-driven validation test로 추가해야 한다. 잘못된
   외부 입력은 panic이 아니라 안정된 validation error와 진단을 반환해야 한다.

3. **Negative consumer fixture가 build graph에 연결되지 않았다.**

   **해결.** fixture를 expected-failure run step에 연결해 exit 1과 ZIGO007 stderr를 함께
   검사하며, 성공 로그에는 자식 stderr가 노출되지 않는다.

   `tests/fixtures/invalid-project`는 ZIGO007 collision을 만들지만 어떤 test step이나 CI 명령도
   이를 실행하지 않는다. child process의 예상 non-zero exit와 `error[ZIGO007]` stderr를 함께
   검사해야 reflection→enrichment→generator 진단 경계를 증명할 수 있다.

### P1 — 다음 보강

4. **`build.zig`의 사용자 옵션 분기는 대부분 간접 검증뿐이다.**

   **부분 해결.** raw package path/name 검증을 `src/build_options.zig`의 pure helper로 분리해
   invalid path component와 Go keyword를 직접 검사한다. public package 충돌, 없는 `go.mod`,
   `.dynamic` linkage, framework/system flag 수집의 build-graph fixture는 후속 범위다.

   raw package의 정상 세 모드는 예제로 검증되지만 invalid path/Go keyword, public package와의
   충돌, 없는 `go.mod`의 Go 1.23/1.24 생성, `.dynamic` linkage, framework/system flag 수집은
   직접 test가 없다. pure path/name helper를 별도 module로 추출해 unit test하고, build graph
   결과가 필요한 경우 최소 fixture project를 두는 편이 적절하다.

5. **Semantic parser의 실패 공간과 fuzz test가 없다.**

   **부분 해결.** malformed/truncated JSON, unknown kind, missing field, defaults, 중첩 type과
   parser/serialize OOM을 직접 검사한다. 장시간 corpus fuzz step은 후속 범위다.

   현재 semantic test는 기본 int fixture의 byte-identical round trip 하나다. malformed/truncated
   JSON, unknown kind, missing required field, 잘못된 scalar width, 중첩 callback/slice/error-union,
   parser OOM을 직접 검증하지 않는다. 작은 corpus 기반 table test 뒤 별도 `test:fuzz` step에서
   `std.testing.fuzz`를 적용할 가치가 있다.

6. **실행 파일의 process 계약이 parser unit test보다 약하다.**

   **부분 해결.** `zigo-gen`의 help/parse/stale/ABI/invalid-semantic 계약은 실제 process로
   고정했다. reflector와 snapshot 실행 파일의 process fixture는 후속 범위다.

   `src/main.zig`, `src/reflect/main.zig`, `snapshot_main.zig`에는 직접 테스트가 없다. CLI parser는
   검증되지만 help 0, parse error 2, stale/ABI failure 1, invalid semantic/lock의 진단과 출력 보존을
   실제 process exit 기준으로 고정하지 않는다. subprocess fixture로 stdout/stderr와 exit code를
   함께 검사해야 한다.

### P2 — 회귀 국소화 개선

7. **Lowering 결과를 구조체 수준에서 직접 검증하지 않는다.**

   **해결.** receiver, out/return slice role, error payload, usize/isize와 enum tag를
   `abi.Program` 수준에서 검사한다.

   golden은 최종 문자열을 잘 잡지만 receiver, out slice의 pointer/length/written 역할, return
   slice, error payload out, usize/isize, enum tag lowering 실패를 `abi.Program` 수준에서 바로
   설명하지 못한다. 작은 table-driven `lower.semanticDocument` test가 실패 원인 국소화에 좋다.

8. **Golden case 자체의 compile smoke가 없다.**

   현재 golden은 byte 비교이며 generated shim/header/Go를 그 case 디렉터리에서 직접 compile하지
   않는다. 실제 examples가 대부분의 조합을 보완하지만 새 golden-only 조합은 문법 오류를 놓칠
   수 있다. golden fixture manifest에 compile 가능 여부를 두고 가능한 case만 Zig/Go compile
   smoke에 연결하는 방식이 적절하다.

9. **Snapshot update 경로의 실패 주입이 약하다.**

   compare에는 allocation-failure sweep이 있지만 `updateGolden`의 OOM과 중간 filesystem 실패는
   없다. 이 명령은 개발 도구이고 source generator의 원자성보다 위험도가 낮으므로 후순위다.

## 충분히 강한 영역

- ZIGO001–ZIGO009 diagnostic snapshot과 ZIGO010 무결성 회귀가 존재한다.
- generator는 invalid semantic/lock과 allocation failure 전 출력 보존을 검증한다.
- errors lock은 예약 코드, duplicate/reuse, append-only transition을 직접 검증한다.
- ABI diff는 signature, identity, constructor, appended error와 OOM을 검증한다.
- reflection은 public discovery, owner-qualified selector, generic specialization과 AST failure를
  직접 검증한다.
- emission은 direct unit보다 complex golden, 8개 build graph, Go compile/runtime/race의 다층
  검증이 더 적합하며 현재 이 경로는 비교적 강하다.

## 권장 구현 순서

1. ~~8개 example의 `test` step을 통일하고 CI에서 14개 테스트를 실행한다.~~
2. ~~semantic 참조 무결성을 validator error로 바꾸고 panic 재현 fixture를 고정한다.~~
3. ~~unused invalid-project를 expected-failure integration test로 연결한다.~~
4. build graph의 나머지 옵션 fixture와 별도 fuzz step을 추가한다.
5. golden compile smoke와 snapshot update 실패 주입으로 실패 원인을 더 좁힌다.
