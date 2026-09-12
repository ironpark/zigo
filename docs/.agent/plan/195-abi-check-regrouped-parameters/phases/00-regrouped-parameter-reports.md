---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test`가 통과하고 새 테스트 두 개가 그 판정을 고정한다.
> NEXT: none

# 재구성된 파라미터 목록의 정확한 보고

## Planned Work

- C 선언 비교에서 값 매개변수와 flattened 필드를 같은 선언으로 봅니다(`cRoleEqual`).
  `field_index`는 provenance이므로 비교에서 뺍니다.
- `signatureEqual`을 `cSignaturesEqual`로 좁히고 Go 표면 비교를 분리합니다.
  written hint 메시지는 목록이 정렬돼 있을 때만 씁니다.
- 파라미터 목록이 어긋났을 때(`sameParameterShape`가 거짓)를 판정합니다. C 선언이 그대로면
  `Go parameter surface changed` 한 줄, Go 표면도 그대로면 아무것도 쓰지 않습니다.
- 주석별 검사(retention, adapter, callback error, callback failure, stream buffer)는 목록이
  정렬돼 있을 때만 실행합니다. 어긋난 짝을 비교하면 없던 변경이 생깁니다.
- Go 표면 비교를 Go 매개변수 토큰 단위(`GoParams`)로 바꿉니다. 값 반환 비교와 반환
  semantic 비교는 그대로 둡니다.
- 회귀 테스트 두 개를 추가합니다: 필드가 옵션 구조체를 떠나는 변경은 한 줄 보고,
  위치를 지킨 flatten 재구성은 무보고.
- `docs/build-and-ship/generated-files-and-ci.md`의 ABI 기준 절에 새 보고를 설명하고
  `CHANGELOG.md`의 Unreleased에 Fixed 항목을 씁니다.

## Done When

- `zig build test`가 통과하고 새 테스트 두 개가 그 판정을 고정한다.
- 실제 예제 문서로 확인했을 때, phase 0에서 했던 재구성이 정확히 한 줄
  (`Go parameter surface changed`)을 낸다.
- 기존 메시지 어휘가 각자의 변경에서 그대로 나온다: `signature changed`(flatten 필드 추가),
  `parameter written hint changed (C signature)`(written hint 변경),
  `callback failure result changed`, `stream staging buffer resized`.
- 예제의 `zig build go-check abi-check`가 통과한다(기준선은 커밋된 semantic).
- 문서 링크 검사가 깨끗하다.
