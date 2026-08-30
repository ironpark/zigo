# SCOPE

- root test discovery와 모듈별 test inventory
- semantic/validation/lowering/emission/generator/ABI/error lock/reflection/snapshot/build API
- allocator failure, filesystem mutation, FFI ownership 및 native/cross-target CI 경로

# CONTEXT

## Current implementation and bottlenecks

`build.zig`는 9개 test artifact와 2개 generator golden case를 조합해 53개 테스트를 실행한다.
generator가 `emit`, `lower`, `validate`, `naming`을 import하므로 test 0개 파일도 일부는 상위
통합 테스트로 실행되지만, 분기별 원인을 국소화하기 어렵고 build API helper는 test root에서
직접 import하기 어렵다.

## Target structure and invariants

테스트 공백은 파일별 test 수가 아니라 계약별 증거로 판정한다. 성공 golden만 있는 경로와
실제 compile/run 경로를 구분하고, allocator 소유 코드는 OOM sweep, filesystem 코드는 tmpDir,
FFI 수명은 native counter 또는 실제 소비자 테스트를 요구한다.
