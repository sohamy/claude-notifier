# claude-notifier

Claude Code 가 작업을 끝내면 **윈도우 토스트 알림 + 소리**로 알려줍니다.
다른 창에서 딴짓하다가도 "끝났나?" 하고 터미널을 들여다볼 필요가 없어집니다.

```
┌──────────────────────────────────────────┐
│ ✅ my-project — 작업 완료                │
│ 테스트 코드 깨진 것 좀 고쳐줘            │
│ 소요 2분 14초 · D:\work\my-project       │
└──────────────────────────────────────────┘
```

마지막으로 뭘 시켰는지, 얼마나 걸렸는지, 어느 프로젝트인지가 알림에 함께 나옵니다.

## 설치

```powershell
# 모든 프로젝트에 적용 (권장)
powershell -NoProfile -ExecutionPolicy Bypass -File D:\claude-notifier\install.ps1

# 이 프로젝트에서만
powershell -NoProfile -ExecutionPolicy Bypass -File D:\claude-notifier\install.ps1 -Scope Project
```

`settings.json` 의 `hooks.Stop` 에 훅 한 줄을 추가합니다. 기존 설정은 건드리지 않고,
수정 전 `settings.json.bak-<날짜>` 로 백업합니다.

실행 중인 Claude Code 세션이 있으면 `/hooks` 로 등록 상태를 확인하거나 세션을 재시작하세요.

## 먼저 시험해보기

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\claude-notifier\test.ps1 -IncludeHook
```

알림이 안 보이면 알림 센터(`Win`+`N`)를 확인하세요. 아무것도 없으면
**설정 → 시스템 → 알림** 에서 알림이 꺼져 있거나 집중 모드가 켜져 있는지 보세요.

## 제거

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\claude-notifier\uninstall.ps1
```

claude-notifier 훅만 골라 지우고 다른 훅은 그대로 둡니다.

## 설정 — `config.json`

| 항목 | 기본값 | 설명 |
|---|---|---|
| `enabled` | `true` | `false` 로 두면 훅은 남겨둔 채 알림만 끕니다 |
| `sound` | `"default"` | `"none"` 이면 무음, `.wav` 경로를 주면 그 파일을 재생 |
| `minSeconds` | `0` | 이 초보다 짧게 끝난 턴은 알림 생략 (예: `30` → 짧은 대화는 조용히) |
| `includePrompt` | `true` | 마지막 지시 내용을 알림 본문에 표시 |
| `promptMaxLength` | `70` | 지시 내용 표시 길이 (넘으면 `…`) |
| `includeProject` | `true` | 제목에 프로젝트 폴더명 표시 |
| `quietHoursStart` | `""` | 방해 금지 시작 (예: `"23:00"`). 비우면 사용 안 함 |
| `quietHoursEnd` | `""` | 방해 금지 종료 (예: `"08:00"`). 자정을 넘겨도 됩니다 |

고친 내용은 다음 알림부터 바로 반영됩니다. 재시작 필요 없습니다.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `hook.ps1` | Stop 훅 본체. stdin JSON 을 읽어 문구를 만들고 `notify.ps1` 을 띄웁니다 |
| `notify.ps1` | 실제 토스트 표시 + 소리 재생 |
| `install.ps1` / `uninstall.ps1` | `settings.json` 훅 등록 / 해제 |
| `test.ps1` | 알림 동작 확인 |
| `config.json` | 설정 |
| `logs/notifier.log` | 알림 발생 및 생략 기록. 문제 생기면 여기부터 |

## 동작 방식

1. Claude Code 가 응답을 마치면 `Stop` 훅이 `hook.ps1` 을 호출하고
   `cwd`, `transcript_path` 등이 담긴 JSON 을 stdin 으로 넘깁니다.
2. `hook.ps1` 이 transcript(`.jsonl`) 뒤쪽을 훑어 **마지막 사용자 지시**와 그 시각을 찾고,
   현재 시각과의 차이로 소요 시간을 계산합니다.
3. `notify.ps1` 을 **별도 프로세스로** 띄우고 즉시 종료합니다 — Claude Code 를 붙잡지 않습니다.
4. 알림 표시에 실패해도 훅은 항상 `exit 0` 이라 작업 흐름이 깨지지 않습니다.

## 알아둘 점

- **Windows PowerShell 5.1(`powershell.exe`) 로 실행해야 합니다.** 토스트에 쓰는 WinRT API 가
  PowerShell 7(`pwsh`)에서는 바로 잡히지 않습니다. 설치 스크립트가 `powershell` 로 등록하니
  훅 명령을 직접 손대지만 않으면 됩니다.
- WinRT 토스트가 안 되는 환경에서는 자동으로 풍선 알림(`NotifyIcon`)으로 넘어갑니다.
- `.ps1` 파일은 **UTF-8 BOM** 으로 저장돼 있습니다. BOM 을 빼면 PowerShell 5.1 이 한글을
  ANSI 로 읽어 구문 오류가 납니다. 편집기에서 인코딩을 바꾸지 마세요.
- 소리를 바꾸려면 `config.json` 의 `sound` 에 `.wav` 경로를 넣으세요.
  `C:\Windows\Media\` 에 쓸 만한 것들이 있습니다 (`Alarm03.wav`, `notify.wav` 등).
