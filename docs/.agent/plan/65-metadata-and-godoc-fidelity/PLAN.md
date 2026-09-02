---
description: semantic.json symbol 네임스페이스 정정, Go doc comment 문법·그룹 공유, 패키지 doc 생성
plan_status: in-progress
registered_at: "2026-09-02T04:35:12Z"
---
> NEXT: 함수 심볼 규칙을 한 함수로 모으고 `semantic.json`의 `symbol`을 헤더 export 이름과 일치시킨다. ([Phase 0](phases/00-symbol-rule.md))

# Phases

- [x] [Phase 00: 함수 심볼 규칙 단일화와 semantic.json 정정](phases/00-symbol-rule.md)
- [ ] [Phase 01: doc 수집 규칙: 그룹 주석과 연속 선언 공유](phases/01-doc-collection.md)
- [ ] [Phase 02: Go doc 출력 형식과 필러 정리](phases/02-doc-rendering.md)
- [ ] [Phase 03: 패키지 doc 생성](phases/03-package-doc.md)

# Shared Verification

- `zig build test --summary all`.
- `for e in examples/*; do (cd $e && zig build test go-check abi-check --summary all); (cd $e/go && go vet ./... && go test -count=1 ./...); done` + purego 4개.
- 생성물 갱신: 예제는 `zig build go`(purego `-Dpurego=true`), 골든은 `zig build snapshot -- <expected> <actual> --update-snapshots`에 실패 출력의 actual 경로를 넘긴다(`.zig-cache`를 `ls`로 잡지 말 것).
- `git status`로 의도 밖 생성물 변경 확인.

# Decisions That Constrain Ordering

0은 독립. 1 → 2, 1 → 3. 2와 3은 병행 가능. phase 0은 `semantic.json` 전면 변경이므로 단독 커밋. phase 2·3은 골든 변화가 크므로 각각 커밋.

# Next Implementation Target

함수 심볼 규칙을 한 함수로 모으고 `semantic.json`의 `symbol`을 헤더 export 이름과 일치시킨다.
