# SCOPE

- example test step과 CI discovery
- semantic type/constructor referential integrity
- expected-failure child process fixture
- semantic parser error/OOM 및 direct lowering test
- pure build option validation과 최종 문서/전체 matrix

# CONTEXT

## Current implementation and bottlenecks

root test는 53개를 실행하지만 example 14개는 CI에서 빠지고 5개 example은 test step도 없다.
validator는 지원 type form만 확인하고 참조 선언의 존재를 확인하지 않아 lower의 `unreachable`이
외부 입력으로 도달 가능하다. invalid-project는 추적되지만 어떤 build step에도 연결되지 않는다.

## Target structure and invariants

모든 외부 semantic 오류는 panic이 아닌 명시적 error/diagnostic이어야 한다. example test는 각
소비자 build graph가 소유하며 CI가 명시적으로 실행한다. negative process test는 stderr를 캡처해
성공 로그를 오염시키지 않고 정확한 exit code와 진단을 검사한다. allocator를 받는 parser/lowering
test는 `std.testing.allocator`와 필요한 OOM sweep을 사용한다.
