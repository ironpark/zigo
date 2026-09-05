# GOALS

## Problem and the end result from the user's point of view

`docs/.agent/design/10-ownership-model.md` 1절이 보여주듯 소유권은 handle, buffer, token 세 형태로
수렴해 있지만, 그 형태를 알아내는 코드는 lowering(`release_symbol` 루프, `returnStringRole`,
`sliceReturnElement`), emit(`raw.releaseFunction`, `common.releaseReceiverCName`,
`writeCgoSliceReturn`/`writePuregoSliceReturn`의 release 분기, materialized byte 특례), validate
(`releaseTargetIssue`, `materializedReleaseTargetIssue`, `ownedReturnIsWrappable`,
`releasableSliceReturnElement`)에 흩어져 있다. 이 계획이 끝나면 lowering이 함수마다 하나의
`abi.Ownership` 레코드와 파라미터별 `ParamOwnership`을 세우고, emit은 레코드만 읽으며, validate는
release 후보를 찾는 helper 하나를 lowering과 공유한다. 사용자가 보는 생성물과 `semantic.json`은
바뀌지 않는다.

## Measurable goals

- `AbiFn.ownership: abi.Ownership`과 `AbiFn.param_ownership: []const ParamOwnership`이 존재하고,
  `lower.zig` 테스트가 golden case의 대표 함수마다 기대 레코드를 단언한다.
- `AbiFn.release_symbol`이 사라지고, `raw.releaseFunction`과 `common.releaseReceiverCName`이 심볼로
  `AbiFn`을 다시 찾는 일이 없어진다.
- ZIGO015, ZIGO016, ZIGO048의 release 후보 찾기가 `lower.releaseTarget` 하나를 부른다.
- payload를 벗기는 함수는 `TypeNode.errorPayload` 위의 두 개(소유권 질문, 호출 규약 질문)로 준다.
- 매 phase마다 `zig build test`가 녹색이고 `tests/generator_cases` 44개 golden이 바이트 동일하다.

## Supported scope and non-goals

- 범위: `src/gen/ir/abi.zig`, `src/gen/lower.zig`, `src/gen/emit/{raw,purego,common,public,shim,materialized}.zig`,
  `src/gen/validate/{ownership,materialized,functions}.zig`, 설계 문서 `01-architecture.md`, `10-ownership-model.md`, `bindings.md`.
- 비범위: `semantic.json` 계약과 `ir_version`, `abi-diff` 보고 문구, arena 스코프 API, zero-copy view,
  `ownership = library` enum 값 제거, Go 이외 언어.

## Reference source / commit / license

- `docs/.agent/design/10-ownership-model.md` 2절(레코드 정의, 행 매핑, 대체 코드 목록).
- 계획 109가 `must_variant`, `reaches_callback_errors`에 적용한 "lowering이 한 번 결정하고 기록한다" 규칙.
- 리포지토리 MIT 라이선스, 외부 소스 없음.

## Completion criteria for the whole plan

- 위 측정 목표를 모두 만족하고 네 phase가 각각 커밋되어 `done`이다.
- `CHANGELOG.md` `[Unreleased]`에 내부 변경으로 기록되어 있다.
