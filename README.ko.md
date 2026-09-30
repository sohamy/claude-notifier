# claude-notifier

Claude Code 가 작업을 끝내면 데스크톱 알림으로 알려줍니다.

*[English README](README.md)*

Claude Code 는 터미널에서 돌기 때문에 오래 걸리는 작업은 계속 쳐다보거나 아예
잊어버리게 됩니다. 이 도구는 Claude 가 응답을 마치는 순간 윈도우 토스트를 띄워,
창을 옮기지 않고도 무엇이 끝났는지 알 수 있게 합니다.

```
+------------------------------------------+
|  my-project - 작업 완료                  |
|  테스트 깨진 것 좀 고쳐줘                |
|  소요 2분 14초 - D:\work\my-project      |
+------------------------------------------+
```

마지막으로 뭘 시켰는지, 얼마나 걸렸는지, 어느 프로젝트인지가 함께 나옵니다.

## 요구 사항

- Windows 10 또는 11
- Windows PowerShell 5.1 (`powershell.exe`) — 윈도우에 기본 포함, 설치할 것 없음
- Claude Code

PowerShell 7(`pwsh`)이 깔려 있어도 상관없지만, 알림 자체는 5.1 에서 돕니다.
이유는 [알아둘 점](#알아둘-점) 에 적었습니다.

## 설치

원하는 위치에 clone 한 뒤 그 폴더에서 설치 스크립트를 실행하세요.

```powershell
git clone https://github.com/sohamy/claude-notifier.git
cd claude-notifier

# 모든 프로젝트에 적용 (권장)
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# 이 프로젝트에서만
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Scope Project
```

Claude Code 의 `settings.json` 에 `Stop` 훅 한 줄을 추가하고, clone 한 위치를
가리키게 합니다. 기존 훅과 설정은 건드리지 않으며 수정 전
`settings.json.bak-<날짜>` 로 백업합니다.

`-Scope User` 는 `%USERPROFILE%\.claude\settings.json` 에, `-Scope Project` 는
현재 폴더의 `.claude\settings.json` 에 씁니다.

다시 실행해도 안전합니다 — 중복 추가 대신 경로만 갱신합니다.

## 사용법

**따로 실행할 건 없습니다.** 평소처럼 Claude Code 를 쓰면 응답이 끝날 때마다
알림이 뜹니다.

세션 도중에 설치했다면 Claude Code 를 한 번 재시작해 훅을 읽게 하세요.
`/hooks` 로 등록됐는지 확인할 수 있습니다.

아래는 전부 선택 사항입니다. `config.json` 을 고쳐 저장하면 다음 알림부터
바로 반영되고, 재시작은 필요 없습니다.

### 짧은 작업에는 알림 끄기

가장 많이 쓰게 되는 설정입니다. 한두 마디 주고받을 때마다 울리면 금방 시끄러워집니다.

```json
"minSeconds": 30
```

30초보다 오래 걸린 작업만 알립니다.

### 소리만 끄기 (배너는 유지)

```json
"sound": "none"
```

### 원하는 소리로 바꾸기

```json
"sound": "C:\Windows\Media\Alarm03.wav"
```

JSON 이라서 백슬래시는 두 개로 씁니다. `C:\Windows\Media\` 에 쓸 만한 게 많습니다.
`ms-winsoundevent:Notification.Looping.*` 계열은 알람용이라 완료 알림에는
과하게 울리니 피하세요.

### 밤에는 조용히

```json
"quietHoursStart": "23:00",
"quietHoursEnd": "08:00"
```

자정을 넘기는 구간도 그대로 쓰면 됩니다.

### 잠깐 전부 끄기

```json
"enabled": false
```

훅은 그대로 두고 알림만 멈춥니다. 나중에 다시 설치할 필요가 없습니다.

### 알림이 안 뜰 때

알림 센터(`Win`+`N`)를 먼저 보세요. 거기에도 없으면 알림이 꺼져 있거나 집중
모드가 켜진 경우입니다 — **설정 → 시스템 → 알림**.

그다음은 `logs\notifier.log` 입니다. 띄운 알림은 모두 기록되고, 건너뛴 경우에는
그 이유(너무 짧음, 방해 금지 시간, 비활성화)가 적힙니다. 로그가 비어 있으면
훅이 아예 호출되지 않은 것이니 `/hooks` 를 확인하세요.

## 설정

| 항목 | 기본값 | 설명 |
|---|---|---|
| `enabled` | `true` | `false` 는 훅을 남긴 채 알림만 끕니다 |
| `sound` | `"default"` | `"none"` 은 무음, `.wav` 경로를 주면 그 파일을 재생 |
| `minSeconds` | `0` | 이 초보다 짧게 끝난 작업은 알림 생략 |
| `includePrompt` | `true` | 마지막 지시 내용을 본문에 표시 |
| `promptMaxLength` | `70` | 이 길이를 넘으면 `…` 로 자름 |
| `includeProject` | `true` | 제목에 프로젝트 폴더명 표시 |
| `quietHoursStart` | `""` | 예: `"23:00"`. 비우면 사용 안 함 |
| `quietHoursEnd` | `""` | 예: `"08:00"`. 자정을 넘겨도 됩니다 |

## 제거

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

이 도구의 훅만 지우고 다른 훅은 그대로 둡니다. Project 범위로 설치했다면
`-Scope Project` 를 붙이세요.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `hook.ps1` | `Stop` 훅 본체. 문구를 만들고 `notify.ps1` 을 띄웁니다 |
| `notify.ps1` | 토스트 표시와 소리 재생 |
| `install.ps1` / `uninstall.ps1` | `settings.json` 훅 등록 / 제거 |
| `config.json` | 설정 |
| `logs/notifier.log` | 알림 발생·생략 기록. 문제 생기면 여기부터 |

## 동작 방식

1. Claude Code 가 응답을 마치면 `Stop` 훅이 `hook.ps1` 을 호출하고 `cwd`,
   `transcript_path` 등이 담긴 JSON 을 stdin 으로 넘깁니다.
2. `hook.ps1` 이 transcript(`.jsonl`) 뒤쪽을 훑어 **마지막 사용자 지시**와 그
   시각을 찾고, 현재 시각과의 차이로 소요 시간을 계산합니다.
3. `notify.ps1` 을 **별도 프로세스로** 띄우고 즉시 반환하므로, Claude Code 가
   토스트를 기다리며 멈추는 일이 없습니다.
4. 훅은 항상 `exit 0` 입니다. 알림이 실패해도 작업 흐름이 깨지지 않습니다.

## 알아둘 점

- **PowerShell 7 이 아니라 Windows PowerShell 5.1 에서 돕니다.** 토스트에 쓰는
  WinRT API 가 `pwsh` 에서는 바로 잡히지 않습니다. 설치 스크립트가 `powershell`
  로 등록해 주니, 훅 명령을 직접 손대지 않으면 신경 쓸 일이 없습니다.
- WinRT 토스트를 쓸 수 없는 환경에서는 풍선 알림(`NotifyIcon`)으로 넘어갑니다.
- **`.ps1` 파일은 UTF-8 BOM 으로 저장돼 있습니다.** BOM 을 빼면 PowerShell 5.1 이
  비ASCII 문자를 ANSI 로 읽어 구문 오류가 납니다. 편집기가 인코딩을 다시
  바꾸지 않도록 주의하세요.
