# 빠른 시작

*[English](QUICKSTART.md) · [자세한 README](README.ko.md)*

## 처음부터

```powershell
git clone https://github.com/sohamy/claude-notifier.git
cd claude-notifier
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

끝입니다. 폴더는 아무 데나 둬도 되고, 설치 스크립트가 그 위치를 알아서 등록합니다.

이미 Claude Code 를 켜둔 상태였다면 **한 번 재시작**하세요. 그래야 훅을 읽습니다.
`/hooks` 로 확인할 수 있습니다.

## 그다음부터 하는 일

없습니다. 평소처럼 Claude Code 를 쓰면 됩니다.

| 상황 | 동작 |
|---|---|
| Claude 가 응답을 마치면 | 토스트가 뜨고 **클릭할 때까지 안 사라집니다** |
| 토스트를 클릭하면 | 그 Claude 터미널 창이 맨 앞으로 옵니다 |
| Esc 로 중단하면 | 알림 안 옵니다 — 이미 키보드 앞이니까요 |

알림에는 마지막에 시킨 내용, 소요 시간, 프로젝트 이름이 같이 나옵니다.

## 시끄러우면

`config.json` 에서 한 줄만 바꾸면 됩니다. 저장하면 다음 알림부터 바로 적용되고
재시작은 필요 없습니다.

```json
"minSeconds": 30
```

30초 넘게 걸린 작업만 알립니다. 짧은 대화에는 조용합니다.

| 원하는 것 | 설정 |
|---|---|
| 소리만 끄기 | `"sound": "none"` |
| 알림이 저절로 사라지게 | `"persistUntilClicked": false` |
| 밤에는 조용히 | `"quietHoursStart": "23:00"`, `"quietHoursEnd": "08:00"` |
| 잠깐 전부 끄기 | `"enabled": false` |

## 안 뜰 때

1. 알림 센터(`Win`+`N`) 확인. 거기도 비었으면 **설정 → 시스템 → 알림** 에서
   알림이 꺼졌거나 집중 모드가 켜졌는지 보세요.
2. `logs\notifier.log` — 알림을 띄웠는지, 건너뛰었다면 그 이유가 적혀 있습니다.
3. 로그가 아예 비었으면 훅이 안 불린 겁니다. `/hooks` 를 확인하세요.

## 제거

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

이 도구의 훅과 클릭 핸들러만 지웁니다. 다른 설정은 그대로 둡니다.
