# Codex Usage Monitor

개인 PC의 Codex Desktop/CLI rollout JSONL을 읽어 프롬프트, 모델, reasoning effort,
서브에이전트와 토큰 사용량을 실시간으로 보여주는 로컬 전용 모니터입니다.

## 특징

- `~/.codex/sessions`를 읽기 전용으로 감시합니다.
- `last_token_usage`를 호출 단위로 저장해 누적 토큰의 중복 집계를 피합니다.
- `session_id`와 `thread_spawn.parent_thread_id`로 부모/자식 작업을 연결합니다.
- `task_started`, `task_complete`, `turn_id`로 실행 중/완료 상태를 구분합니다.
- `codex-auto-review`는 DB에 출처만 보존하고 모든 사용자 합계와 UI에서 제외합니다.
- SQLite offset 체크포인트로 변경된 JSONL의 새 줄만 읽습니다.
- SSE와 10초 폴링으로 브라우저 목록을 자동 갱신합니다.
- 대시보드의 `위젯 켜기` 버튼으로 종료한 데스크톱 위젯을 언제든 다시 실행할 수 있습니다.
- 대시보드는 `오늘`을 기본 조회 기간으로 사용하며 요약과 프롬프트 목록에 함께 적용합니다.
- 외부 npm 패키지, 클라우드 백엔드, 텔레메트리, 인증 토큰이 필요하지 않습니다.

## 요구 사항

- Windows
- Node.js 24 이상 (`node:sqlite` 사용)

## 실행

PowerShell에서 다음 스크립트를 실행하면 숨김 백엔드와 화면 오른쪽 아래 비용 위젯을 시작합니다.
브라우저 대시보드도 열려면 `-Open`을 추가합니다. 위젯 사용법과 로그인 자동 실행은 [WIDGET.md](WIDGET.md)를 참고하세요.

```powershell
.\scripts\Start-Monitor.ps1
```

서비스만 보장하려면:

```powershell
.\scripts\Ensure-Monitor.ps1 -NoWidget
```

기본 주소는 `http://127.0.0.1:47831`입니다. 외부 인터페이스에는 바인딩하지 않습니다.

서비스 종료:

```powershell
.\scripts\Stop-Monitor.ps1
```

## 다른 PC에서 사용

저장소를 원하는 폴더에 clone한 다음 해당 폴더에서 실행합니다. Node.js 24 이상만 필요하며 `npm install`은 필요하지 않습니다.

```powershell
npm test
.\scripts\Start-Monitor.ps1
```

Windows 로그인 자동 실행은 PC마다 선택적으로 등록합니다. clone이나 일반 실행은 자동 실행 설정을 변경하지 않습니다.

```powershell
.\scripts\Install-WidgetStartup.ps1
# 자동 실행 해제
.\scripts\Uninstall-WidgetStartup.ps1
```

Codex 작업 시작 시 호출하는 `AGENTS.md` 설정도 각 PC의 로컬 설정으로 별도 관리합니다. 이 저장소는 해당 설정을 설치하거나 변경하지 않습니다.
업데이트는 `git pull`로 받습니다. 실행 중인 서비스와 위젯은 종료 후 다시 시작해야 변경된 코드가 반영됩니다.
사용량 DB, 원본 대화 로그, PC별 위젯 설정과 자동 실행 바로가기는 Git에 포함하지 않습니다.

## 데이터 위치

- 원본(읽기 전용): `%USERPROFILE%\.codex\sessions`
- SQLite/PID: `%USERPROFILE%\.codex-usage-monitor`
- 서비스 로그: `%LOCALAPPDATA%\CodexUsageMonitor`

환경변수로 변경할 수 있습니다.

- `CODEX_HOME`
- `CODEX_USAGE_MONITOR_STATE_ROOT`
- `CODEX_USAGE_MONITOR_PORT`
- `CODEX_USAGE_MONITOR_LOOKBACK_DAYS`

## API

- `GET /api/health`
- `GET /api/turns?days=today&limit=150` (`today`은 로컬 자정 기준)
- `GET /api/summary?days=today`
- `GET /api/events` (SSE)
- `GET /api/widget` (최근 30초 평균 비용과 5분 시계열)
- `GET /api/widget?minutes=15` (1~60분 범위의 가변 시계열)
- `POST /api/widget/start` (데스크톱 위젯 실행, 이미 실행 중이면 중복 실행하지 않음)
- `POST /api/rescan`

## 정확도 범위

토큰 수치는 Codex가 rollout에 기록한 값입니다. API 환산 USD와 Codex 크레딧은
`config/rate-card.json`의 가격표를 적용한 계산값이며 실제 구독 청구액이나 공급자의
세션별 한도 소비율이 아닙니다. 현재 생성 중인 호출은 마지막 `token_count` 이벤트까지의
부분값으로 보이고, `task_complete`가 기록되면 완료 상태가 됩니다.

## 검증

```powershell
npm test
```
