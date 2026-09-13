---
entry_condition: phase 09가 done이고, out slice 원소마다 Zig union과 C 미러를 오가는 staging을 shim에 새로 쓰기로 정했을 때
perf_phase: false
status: conditional
---
> DONE-WHEN: `fn attributes(out: []Attribute) usize` 모양이 인덱스 접근 없이 바인딩된다.
> NEXT: none

# Tagged union as a slice element

error union 자리는 phase 09가 맡는다. 남은 것은 slice 원소 자리 하나다.

확인한 것: 값 union에는 이미 C 미러 struct와 `zigo<Union>FromRaw`가 있고, out
value-struct slice를 원소마다 되읽는 경로(`zigo<T>SliceCopyFromRaw`)도 있다. 없는 것은
shim 쪽이다. Zig 함수는 진짜 `[]Attribute`에 쓰는데 C는 미러 배열을 넘기므로, shim이
staging `[]Attribute`를 잡고 호출한 뒤 원소마다 미러로 옮겨야 한다. narrow int slice의
`zigo_<name>_slice` staging이 같은 모양이지만, union 변환 자체는 새로 써야 한다.

## Planned Work

- shim이 out union slice마다 staging 버퍼를 잡고, 성공 경로에서 원소마다 미러로 옮긴다.
- 실패 경로와 written 보고가 기존 out slice 규약과 같게 한다.
- Go 쪽 copy-back이 `zigo<Union>SliceCopyFromRaw`를 쓰도록 그 도우미를 낸다.
- ZIGO006의 금지를 out slice 원소 자리에서만 풀고 나머지 중첩은 그대로 막는다.

## Done When

- `fn attributes(out: []Attribute) usize` 모양이 인덱스 접근 없이 바인딩된다.
- 돌아온 Go slice의 원소마다 variant accessor가 있다.
- 지원하지 않는 중첩은 여전히 ZIGO006으로 거절된다.
