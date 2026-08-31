# zigo 사용자 문서

README의 빠른 시작 이후에 필요한 상세 사용법과 운영 정보를 제공한다. 각 주제의 정본은
아래 문서 하나이며, README와 예제는 그 문서를 가리킨다.

## 사용

- [설치와 사용](getting-started.md): 준비 사항, 의존성 추가, 빌드 그래프 연결, 바인딩 선언, 생성·검사와 CI
- [설정과 생성물](configuration.md): `addGoBindings` 옵션, 선언 메타데이터, 생성 파일 관리
- [예제](examples.md): 예제 10종이 각각 다루는 범위와 실행 방법

## 배포와 운영

- [공유 라이브러리와 purego 백엔드](purego.md): 동적 라이브러리 배포, 런타임 로딩, `CGO_ENABLED=0` 빌드
- [제한사항과 운영 주의사항](limitations.md): 지원 범위, FFI 계약과 알려진 제약

## 기여

- [프로젝트 개발](development.md): 저장소 테스트와 예제 검증
- [설계 문서](.agent/design/README.md): 내부 아키텍처, IR, 하강 규칙과 구현 상태
