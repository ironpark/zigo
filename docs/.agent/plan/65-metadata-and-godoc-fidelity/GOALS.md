# GOALS

## Problem and the end result from the user's point of view

사용자가 생성물에서 세 가지를 지적했고 모두 코드로 확인됐다.
1. `semantic.json`의 함수 `symbol`이 실제 export 심볼과 다르다. `src/reflect/walk.zig:187`은 `{prefix}_{name}`만 쓰고, 실제 심볼은 `src/gen/lower.zig:199-210`에서 `{prefix}_{owner}_{name}`(snake)으로 만든다. 예제 04/05/09/10에서 `zg_create`·`zg_deinit` 등이 중복된다. `abi_diff.zig:75-76`은 이 필드를 비교하므로 소유 타입 이동을 놓치는 false negative가 생기고, `symbol`을 읽는 소비자는 잘못된 링커 이름을 받는다.
2. Go doc이 문법적으로 깨진다. `writeGoDoc`(`emit.zig:4357-4383`)이 항상 `// {GoName} ` 뒤에 본문을 접합해 `/// The selection flag bits…` → `// SelectionSilent the selection flag bits…`가 된다. `///`는 Zig 의미대로 바로 다음 선언에만 붙고(`names.zig:192-206`), `//` 그룹 주석은 토크나이저가 버려 보이지 않으며, 문서 없는 형제 함수는 `invokes the bound Zig … operation` 필러(`emit.zig:4411,4413`)를 받는다. `tests/godoc_audit/main.go:78-83`는 이름 접두만 검사해 이를 잡지 못한다.
3. 어떤 생성 파일에도 `// Package …` doc이 없다. 옵션도 없다(`Options` `emit.zig:6-34`에는 `go_package`만). godoc_audit은 `file.Doc`을 보지 않는다.

작업 후: `symbol`이 헤더의 export 이름과 일치하고 한 곳의 규칙에서 나온다. 함수 doc은 이름으로 시작하지 않는 문장을 두 줄 형식으로 내고, 연속 선언은 doc을 공유하며, `//` 그룹 주석도 읽는다. 공개 패키지의 한 파일에 `// Package {name} …` doc이 생성되고 `bindings.zig` 최상위 doc 또는 옵션에서 본문을 가져온다.

## Measurable goals

- 모든 예제 `semantic.json`에서 `symbol`이 유일하고, 생성된 헤더의 export 이름과 1:1로 같다는 테스트.
- `/// The …` 형식 doc fixture가 `// Name\n// The …` 두 줄로 생성되고, 접합 형식은 이름 또는 동사로 이어지는 문장에만 쓰인다.
- 문서 없는 연속 선언이 앞 선언의 doc을 공유한다는 골든. `//` 그룹 주석이 doc으로 반영된다는 골든.
- 공개 패키지에 정확히 한 파일만 `// Package` doc을 가지며 godoc_audit이 이를 단정한다.

## Supported scope and non-goals

지원: `src/reflect/{walk,names}.zig`, `src/gen/{emit,lower,validate,naming,abi_diff}.zig`, `build.zig` 옵션, 골든·예제 재생성, godoc_audit 확장, 문서.
비목표: 헤더/링커 심볼 규칙 변경(실제 심볼은 그대로, 메타데이터만 정정). doc 본문 자체의 재작성. Go doc 렌더링 형식(마크다운 등)의 확장.

## Reference source / commit / license

- 사용자 관찰(Ultrasync `syncnative` 패키지). 저장소 내부 작업, 외부 코드 없음.
- 관련 규칙: Go doc 관례 — 식별자로 시작하는 첫 문장; 패키지 doc은 패키지당 한 파일.

## Completion criteria for the whole plan

- 위 측정 목표 테스트가 모두 통과한다.
- `zig build test --summary all`, 예제 10개의 `go-check`·`abi-check`·`go test`, purego 4개(04, 07, 08, 10) 통과. `go vet ./...`가 각 예제에서 깨끗하다.
- `docs/bindings.md`(doc 주석 규칙, 옵션), `docs/generated-code.md`(메타데이터 계약의 `symbol`), `docs/limitations.md` 갱신.
