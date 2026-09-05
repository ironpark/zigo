# SCOPE

lowering에 소유권 레코드를 추가하고 emit과 validate가 그것을 읽도록 옮긴 뒤 대체된 필드와
중복 helper를 지운다. IR 파일, 생성물, 공개 CLI는 그대로다.

# CONTEXT

## Current implementation and bottlenecks

- `lower.zig` 함수 lowering 루프가 `caller_owned_c_string`, `returnStringRole`, `sliceReturnElement`,
  `abi.materializedReturn/Out`를 각각 계산해 `AbiFn`에 흩어 적고, 별도 루프에서 `release`
  이름을 `release_symbol`로 해석한다.
- `emit/raw.zig`의 `releaseFunction`이 심볼로 `AbiFn`을 다시 찾고 `common.releaseReceiverCName`이
  그 위에서 receiver의 C 이름을 찾는다. cgo와 purego의 slice 반환은 각각 release 여부를 묻는다.
  materialized는 `slice_return_element = u8`을 강제해 같은 byte 경로에 얹힌다.
- `validate/ownership.zig`의 `releaseCandidateParameter`, `releasableSliceReturnElement`,
  `borrowedOpaqueReturn`, `ownedReturnIsWrappable`과 `lower.ownedOpaqueReturn`이 error union과
  optional을 각자 벗긴다.

## Target structure and invariants

- `abi.Ownership = union(enum) { none, borrowed_view, borrowed_copy, handle, buffer }`,
  `abi.ParamOwnership = enum { transient, retained_token, staged_copy, stream }`. 정의는 설계 문서 2.2.
- `lower.ownershipOf(document, functions, function) Ownership`은 검증이 끝난 문서 위에서만 돈다.
  `lower.releaseTarget(document, function) ?ReleaseTarget`은 검증 전에도 안전하게 부를 수 있는
  후보 찾기이고 validate와 `ownershipOf`가 함께 쓴다.
- 불변식: `handle`과 `retained_token`만 `runtime.AddCleanup` 대상이다. `buffer`는 복사 후 즉시
  release한다. 새 변형을 추가하는 사람은 이 둘 중 하나로 표현한다.
- 각 phase는 golden 44개 바이트 동일을 완료 조건으로 삼는다.
