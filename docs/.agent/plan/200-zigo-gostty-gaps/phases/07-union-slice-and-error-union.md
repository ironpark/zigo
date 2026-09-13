---
entry_condition: 0부터 6까지가 done이고, union 값의 extern struct 미러를 slice 원소로 낮추는 경로가 lowering에 이미 있음을 확인했을 때
perf_phase: false
status: conditional
---
> DONE-WHEN: `fn attributes(out: []Attribute) ![]Attribute` 모양이 인덱스 접근 없이 바인딩된다.
> NEXT: none

# Tagged union in slice and error union positions

## Planned Work

- 값 union의 미러 struct를 out slice 원소 타입으로 쓰는 경로를 낮춘다.
- error union payload 자리의 union 값을 기존 값 반환 규약으로 흘린다.
- ZIGO006의 금지를 두 자리에서만 풀고 나머지 중첩은 그대로 막는다.
- 생성된 Go가 원소마다 variant accessor를 갖도록 한다.

## Done When

- `fn attributes(out: []Attribute) ![]Attribute` 모양이 인덱스 접근 없이 바인딩된다.
- 지원하지 않는 중첩은 여전히 ZIGO006으로 거절된다.
