# 설계 문서

이 디렉터리는 zigo의 설계 근거, 내부 표현, ABI 하강 규칙과 구현 기록을 보관한다.
일반적인 설치와 사용 방법은 [사용자 위키](../wiki/README.md)를 참고한다.

| 문서 | 내용 |
|---|---|
| [제약과 리스크](00-constraints.md) | 기술적 제약, 하강 실패 조건과 리스크 등록부 |
| [아키텍처](01-architecture.md) | 빌드 그래프, 공개 빌드 API, 소유권 모델과 ABI 검사 |
| [IR 명세](02-ir-spec.md) | semantic, layout, errors lock 데이터 구조 |
| [ABI 하강 규칙](03-lowering-rules.md) | Zig 타입을 C ABI와 Go API로 변환하는 규칙 |
| [구현 계획](04-implementation-plan.md) | 마일스톤, 디렉터리 구조와 검증 전략 |
| [타입 배치 검토](type-placement-review.md) | named type의 소유 파일과 배치 정책 검토 기록 |
