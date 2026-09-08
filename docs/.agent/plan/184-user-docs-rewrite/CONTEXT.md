# SCOPE

- 제품 진입점: `README.md`, `docs/README.md`, `docs/getting-started.md`, `docs/how-zigo-works.md`, `docs/examples.md`
- 바인딩 작성: `docs/authoring/`
- 빌드·배포: `docs/build-and-ship/`
- 정본 참조: `docs/reference/`
- 플러그인: `docs/plugins/`
- 내부 공개 계약: `docs/internals/`
- 기여자와 예제 문서: `CONTRIBUTING.md`, `examples/*/README.md`, `plugins/*/README.md`
- 제거 대상: `docs/migration-*.md` 및 과거 작성 API 안내

# CONTEXT

## Current implementation and bottlenecks

최상위 사용자 문서 24개와 예제 README가 약 7천 줄이다. README·시작 가이드·최소 예제가 같은 설정을 반복하고, 설정·치트시트·선언 문서가 API 표를 중복하며, `limitations.md`가 각 기능 문서의 제한을 다시 서술한다. ABI와 runtime 내부 설명도 일반 사용자 탐색에 같은 깊이로 노출되어 있다.

## Target structure and invariants

튜토리얼은 단일 기본 경로만, 작업 가이드는 한 가지 사용자 목적만, 참조는 정본 사실만, 내부 문서는 ABI 검토자용 계약만 담는다. 지원 범위, 옵션, 진단, 소유권과 생성 파일에는 각각 하나의 정본을 둔다. 다른 문서는 요약 후 정본으로 연결한다. 플러그인은 자체 홈과 작성·API 참조를 가진다.
