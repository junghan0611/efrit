# bd (beads) 사용 가이드 - AI 에이전트용

> 이 문서는 AI 에이전트가 `bd` (beads) 이슈 트래커를 사용하기 위한 한글 가이드입니다.
> AGENTS.md에 일부 내용을 포함시켜 사용하세요.

## bd란?

**bd (beads)** 는 Steve Yegge가 만든 의존성 기반 이슈 트래커입니다.

- **Git 친화적**: JSONL 파일로 자동 동기화
- **의존성 추적**: 이슈 간 블로킹 관계 관리
- **AI 최적화**: `--json` 출력, ready work 감지

## 설치

```bash
# efrit-ko 레포에서 빌드 스크립트 실행
./build-steveyegge-tools.sh

# 또는 직접 빌드
cd ~/repos/3rd/beads && go build -o bd ./cmd/bd
cp bd ~/.local/bin/
```

## 핵심 명령어

### 초기화
```bash
bd init              # 현재 디렉토리에 .beads/ 생성
bd init --prefix api # 커스텀 prefix (api-1, api-2...)
```

### 이슈 생성
```bash
bd create "버그 수정" -t bug -p 1 --json
bd create "새 기능 추가" -t feature -p 2 --json
bd create "리팩토링" -t task -p 3 --json
```

### 이슈 조회
```bash
bd list                    # 전체 목록
bd list --status open      # 열린 이슈만
bd ready                   # 작업 가능한 이슈 (블로커 없음)
bd show bd-1               # 상세 보기
```

### 이슈 업데이트
```bash
bd update bd-1 --status in_progress  # 작업 시작
bd update bd-1 --priority 0          # 우선순위 변경
bd update bd-1 --assignee agent      # 담당자 지정
```

### 이슈 완료
```bash
bd close bd-1 --reason "수정 완료"
```

### 의존성 관리
```bash
bd dep add bd-1 bd-2       # bd-2가 bd-1을 블로킹
bd dep tree bd-1           # 의존성 트리 시각화
bd dep cycles              # 순환 의존성 감지
```

## 이슈 타입 (-t)

| 타입 | 설명 |
|------|------|
| `bug` | 버그, 오류 |
| `feature` | 새로운 기능 |
| `task` | 일반 작업 (테스트, 문서, 리팩토링) |
| `epic` | 대규모 기능 (하위 작업 포함) |
| `chore` | 유지보수 (의존성, 도구) |

## 우선순위 (-p)

| 값 | 의미 |
|----|------|
| 0 | **Critical** - 보안, 데이터 손실, 빌드 실패 |
| 1 | **High** - 주요 기능, 중요 버그 |
| 2 | **Medium** - 기본값, 일반 작업 |
| 3 | **Low** - 개선, 최적화 |
| 4 | **Backlog** - 나중에 할 것 |

## AI 에이전트 워크플로우

```
1. 작업 확인     → bd ready --json
2. 작업 시작     → bd update <id> --status in_progress --json
3. 구현/테스트   → 코드 작업
4. 새 이슈 발견? → bd create "발견한 버그" -p 1 --deps discovered-from:<parent-id> --json
5. 작업 완료     → bd close <id> --reason "완료" --json
6. 커밋          → .beads/issues.jsonl 파일도 함께 커밋!
```

## 자동 동기화

bd는 Git과 자동으로 동기화됩니다:
- 변경 후 5초 뒤 `.beads/issues.jsonl`로 내보내기
- `git pull` 후 JSONL이 더 최신이면 자동 가져오기
- 수동 export/import 불필요!

---

# AGENTS.md에 추가할 내용

아래 내용을 프로젝트의 `AGENTS.md`에 추가하세요:

```markdown
## 이슈 트래킹: bd (beads)

**중요**: 이 프로젝트는 **bd (beads)** 로 모든 이슈를 관리합니다.
마크다운 TODO 리스트나 다른 트래킹 방법을 사용하지 마세요.

### 필수 명령어

```bash
# 작업 찾기
bd ready --json              # 블로커 없는 작업 가능 이슈

# 이슈 생성
bd create "제목" -t bug|feature|task -p 0-4 --json

# 작업 시작/완료
bd update <id> --status in_progress --json
bd close <id> --reason "완료" --json
```

### 워크플로우

1. `bd ready` 로 작업 가능한 이슈 확인
2. `bd update <id> --status in_progress` 로 작업 시작
3. 코드 구현, 테스트
4. 새 이슈 발견 시: `bd create "제목" --deps discovered-from:<parent-id>`
5. `bd close <id>` 로 완료
6. `.beads/issues.jsonl` 파일과 코드 변경사항 함께 커밋

### 규칙

- 모든 작업은 bd 이슈로 관리
- 항상 `--json` 플래그 사용 (프로그래밍 파싱용)
- 발견된 작업은 `discovered-from` 의존성으로 연결
- "뭘 해야 하나요?" 전에 `bd ready` 먼저 확인
- 마크다운 TODO 리스트 사용 금지
```

---

## 추가 명령어

### 검색 및 통계
```bash
bd search "키워드"           # 텍스트 검색
bd stats                     # 통계
bd stale --days 30           # 오래된 이슈
bd blocked                   # 블로킹된 이슈
```

### 댓글
```bash
bd comment bd-1 "진행 상황 메모"
bd comments bd-1             # 댓글 보기
```

### 정리
```bash
bd cleanup --age 30d         # 30일 지난 완료 이슈 삭제
bd compact                   # 오래된 완료 이슈 압축
```

### 데이터베이스 정보
```bash
bd info                      # DB 및 데몬 정보
bd doctor                    # 설치 상태 점검
bd validate                  # DB 무결성 검사
```

## 파일 구조

```
project/
├── .beads/
│   ├── beads.db           # SQLite DB (커밋하지 않음)
│   └── issues.jsonl       # Git 동기화용 (커밋함!)
├── AGENTS.md
└── ...
```

## 팁

1. **항상 `--json` 사용**: AI 에이전트가 파싱하기 쉬움
2. **`bd ready` 먼저**: 작업 전 블로커 없는 이슈 확인
3. **의존성 활용**: `discovered-from`으로 작업 연결
4. **JSONL 커밋**: 코드와 이슈 상태를 함께 버전 관리

## 관련 도구

- **vc (VibeCoder)**: bd 기반의 AI 에이전트 오케스트레이터
- **beads-mcp**: Claude MCP 서버 통합

## 참고 링크

- [beads GitHub](https://github.com/steveyegge/beads)
- [vc GitHub](https://github.com/steveyegge/vc)
- [Steve Yegge's Vibe Coding Book](https://www.amazon.com/dp/B0F81D3SYF)
