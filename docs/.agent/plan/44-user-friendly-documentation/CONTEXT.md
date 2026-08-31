# SCOPE

루트 README와 공개 사용자 문서의 탐색 구조, 온보딩 순서, 설정·바인딩·생성물 참조 분리, purego와
제한사항의 진입 설명 및 교차 링크를 다룬다. 한국어 문체와 실제 식별자·명령은 유지한다.

# CONTEXT

## Current implementation and bottlenecks

README는 제품 설명과 짧은 코드 조각을 제공하지만 완전한 첫 실행 흐름과 기본/선택 백엔드 선택 기준이
약하다. `docs/getting-started.md`는 입문과 CI·purego를 한 문서에서 다루며,
`docs/configuration.md`는 빌드 옵션, 바인딩 DSL, 타입 모델, 오류와 생성 파일까지 486줄에 모여 있다.
문서 인덱스는 파일 목록 중심이라 증상이나 목적에서 출발하기 어렵다.

## Target structure and invariants

README는 평가와 첫 성공에 집중하고, 문서 인덱스는 사용자 여정을 안내한다. 시작 가이드는 기본 cgo
경로만 단계별로 설명한다. 빌드 설정, `bindings.zig` 선언, 생성물·CI는 별도 정본으로 분리하며,
purego는 선택 백엔드 문서로 남긴다. 동일한 사실을 여러 곳에 장문으로 복제하지 않고 링크하며,
모든 코드와 명령은 현재 공개 API 이름을 사용한다.
