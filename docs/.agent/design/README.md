# 설계 문서

이 디렉터리는 zigo의 설계 근거, 내부 표현, ABI 하강 규칙과 구현 기록을 보관한다.
일반적인 설치와 사용 방법은 [사용자 문서](../../README.md)를 참고한다.

| 문서 | 내용 |
|---|---|
| [제약과 리스크](00-constraints.md) | 기술적 제약, 하강 실패 조건과 리스크 등록부 |
| [아키텍처](01-architecture.md) | 빌드 그래프, 공개 빌드 API, 소유권 모델과 ABI 검사 |
| [IR 명세](02-ir-spec.md) | semantic, layout, errors lock 데이터 구조 |
| [ABI 하강 규칙](03-lowering-rules.md) | Zig 타입을 C ABI와 Go API로 변환하는 규칙 |
| [구현 계획](04-implementation-plan.md) | 마일스톤, 디렉터리 구조와 검증 전략 |
| [구현 상태](05-implementation-status.md) | 구현된 것, 설계와의 차이, 미구현 항목 |
| [공유 라이브러리 계약](06-shared-library-contract.md) | 동적 아티팩트 파일명, export 심볼과 런타임 로딩 계약 (영문) |

00~04는 현재 구현을 서술한다. 설계 시점과 달라진 결정과 아직 없는 기능은
[구현 상태](05-implementation-status.md)에 모아 두었다.
