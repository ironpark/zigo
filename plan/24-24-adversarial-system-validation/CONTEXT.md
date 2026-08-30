# SCOPE

- 베이스라인과 반복 생성 결정성
- stale 생성물과 ABI mutation 검출
- 생성 실패 원자성 및 errors.lock append-only 계약
- 자동 discovery, 대형 API, 이름/파일/패키지 배치, 선택적 gofmt
- callback/cleanup 수명주기와 race 검증
- host 및 Windows 교차 타깃 compile gate

# CONTEXT

## Current implementation and bottlenecks

단위 테스트와 8개 소비자 예제가 존재하지만 검증 명령이 분산되어 있고, build graph 수준의
부정 실험 결과가 한곳에 정리되어 있지 않다. 특히 성공해야 하는 명령만 실행하면 stale 및
ABI gate가 실제 변형을 거부하는지, 실패 전 출력이 보존되는지 증명되지 않는다.

## Target structure and invariants

실험은 임시 복제본 또는 `std.testing.tmpDir`를 사용해 추적 파일을 오염시키지 않는다.
성공 실험은 exit 0과 결과 동등성을, 부정 실험은 예상된 비영 exit와 구체 진단을 동시에
확인한다. 생성 실패 전후 파일 트리는 byte-identical이어야 하고, 명시적 Close와 cleanup은
중복 해제나 callback handle 누수를 만들지 않아야 한다.
