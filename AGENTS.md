# Codex Usage Monitor

- 이 저장소는 개인 PC에서만 실행되는 로컬 도구다. 외부 주소에 바인딩하거나 사용량 데이터를 업로드하지 않는다.
- 원본 Codex JSONL은 항상 읽기 전용으로 취급한다.
- `codex-auto-review`는 사용자 합계에서 제외한다.
- 세션 귀속은 시간 추정보다 `session_id`, `parent_thread_id`, `turn_id`를 우선한다.
- 변경 후 `npm test`와 실제 `/api/health`, `/api/turns` 응답을 검증한다.
