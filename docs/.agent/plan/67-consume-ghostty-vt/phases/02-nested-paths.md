---
completed_at: "2026-09-02T06:34:33Z"
depends_on:
- "67-consume-ghostty-vt#0"
perf_phase: false
status: done
---
> DONE-WHEN: `root.unicode.codepointWidth`·3단계 fixture 골든에 심볼·Go 이름·identity·doc이 기대대로 있고, 기존 골든이 불변이다.
> NEXT: none

# N단계 바인딩 경로

## Planned Work

- `walk.zig`: `pathOwner`/`pathMember`/`pathContainer`를 세그먼트 walk로 교체, `containerHasPath` 재귀, `namespace`에 점 경로 저장. `.discover` 재귀 옵트인 추가.
- `naming.functionSymbolAlloc`: 세그먼트별 snake `_` 결합. 1단계 결과 불변 테스트.
- `emit.zig rawGoNameAlloc`·`callbackTypeBaseNameAlloc`: 세그먼트 Pascal 결합. `writeTargetCall`은 점 경로로 그대로 동작함을 테스트로 고정.
- `names.zig scanMembers`: 재귀 시 부모 이름을 이어 붙인 lexical 경로로 `functionOwner` 대조. 중첩 함수의 doc·파라미터 이름 수집 테스트.
- `abi_diff`: `functionIdentity`가 `a.b.c.fn`으로 나오는지, 심볼 규칙 변경이 기존 1단계 심볼을 바꾸지 않는지 테스트. 바뀐다면 `legacyFunctionSymbolAlloc` 선례로 이행 허용.
- fixture: `tests/generator_cases`에 2단계·3단계 네임스페이스 struct와 그 안의 함수·타입 메서드. 예제 하나(09-type-relations 또는 새 `11-nested-namespaces`)에 실제 사용.
- `docs/bindings.md` 경로 문법 절 갱신.
- 마무리로 gostty에서 facade 제거 후 직접 경로로 `zig build go && go test` 확인(결과만 보고, gostty 커밋은 사용자).

## Done When

- `root.unicode.codepointWidth`·3단계 fixture 골든에 심볼·Go 이름·identity·doc이 기대대로 있고, 기존 골든이 불변이다.
- gostty 직접 바인딩 확인 결과가 보고된다.
