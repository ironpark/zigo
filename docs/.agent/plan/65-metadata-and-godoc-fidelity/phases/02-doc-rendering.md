---
depends_on:
- "65-metadata-and-godoc-fidelity#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `SelectionSilent the …` 류 접합이 어떤 골든에도 없다(테스트로 단정).
> NEXT: none

# Go doc 출력 형식과 필러 정리

## Planned Work

- `writeGoDoc`: 접합 조건을 "이름으로 시작 또는 소문자 동사로 시작"으로 좁히고, 나머지는 `// Name\n// <본문>` 두 줄 형식. 관사·대명사 목록은 상수로 둔다.
- 필러 문구를 한 문장 사실 서술로 정리.
- `tests/godoc_audit/main.go`: 첫 줄이 `name` 단독인 두 줄 형식을 허용. 접합 형식은 기존 규칙 유지.
- `emit.zig` 단위 테스트: `The selection flag bits…` fixture → 두 줄, `reports …` fixture → 접합, 이름 중복 fixture → 중복 제거.
- 골든·예제 재생성.

## Done When

- `SelectionSilent the …` 류 접합이 어떤 골든에도 없다(테스트로 단정).
- godoc_audit이 모든 예제·골든에서 통과.
