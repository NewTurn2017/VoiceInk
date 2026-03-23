<div align="center">

# VoiceInk

**Mac에서 말하면 텍스트로 — 빠르고 정확한 음성 입력 도구**

[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple&logoColor=white)](#requirements)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

<div align="center">

https://github.com/NewTurn2017/VoiceInk/raw/main/assets/voiceink.mp4

</div>

---

## What is VoiceInk?

VoiceInk은 macOS 메뉴바에서 동작하는 **음성-텍스트 변환(STT) 앱**입니다.
단축키 하나로 녹음을 시작하고, 변환된 텍스트가 현재 커서 위치에 자동으로 입력됩니다.

### Key Features

- **Global Hotkey** — 어떤 앱에서든 단축키로 즉시 녹음 시작/종료
- **Local STT** — Qwen3-ASR 모델을 활용한 온디바이스 음성 인식 (인터넷 불필요)
- **Cloud STT** — 클라우드 API 연동으로 높은 정확도 지원
- **Hold-to-Talk / Toggle** — 누르고 있기 또는 토글 두 가지 녹음 모드
- **Recording Overlay** — 녹음 중임을 시각적으로 확인할 수 있는 오버레이
- **Transcript History** — 변환 기록 저장 및 검색
- **Menu Bar App** — 독(Dock)에 표시되지 않는 가벼운 메뉴바 앱

---

## Requirements

| 항목 | 최소 요구 |
|------|-----------|
| macOS | 14.0 (Sonoma) 이상 |
| Chip | Apple Silicon 권장 (Local STT) |
| Xcode | 16.0 이상 (빌드 시) |

---

## Installation

### Homebrew (Recommended)

```bash
brew tap NewTurn2017/tap
brew install --cask voiceink
```

### Manual Download

[GitHub Releases](https://github.com/NewTurn2017/VoiceInk/releases)에서 최신 DMG를 다운로드하세요.

### Build from Source

```bash
git clone https://github.com/NewTurn2017/VoiceInk.git
cd VoiceInk
open VoiceInk.xcodeproj
# Xcode에서 ⌘R로 빌드 및 실행
```

---

## Quick Start

1. **VoiceInk을 실행**하면 메뉴바에 마이크 아이콘이 나타납니다
2. **마이크 권한**을 허용하세요 (첫 실행 시 자동 요청)
3. **단축키** (기본: `⌥ Space`)를 눌러 녹음을 시작합니다
4. 말을 마치면 다시 단축키를 누르거나, Hold-to-Talk 모드에서는 키를 놓으세요
5. **변환된 텍스트**가 현재 커서 위치에 자동으로 입력됩니다

### Settings

메뉴바 아이콘 클릭 → **Settings**에서 다음을 설정할 수 있습니다:

- **Engine** — Local (Qwen3-ASR) 또는 Cloud 선택
- **Model Size** — Local 엔진의 모델 크기 선택
- **Hotkey** — 글로벌 단축키 변경
- **Hold-to-Talk** — 녹음 모드 전환
- **Cloud API Key** — Cloud STT 사용 시 API 키 입력

---

## Architecture

```
VoiceInk/
├── AppState.swift           # 앱 상태 관리 (@MainActor, ObservableObject)
├── STT/
│   ├── STTEngine.swift      # STT 엔진 프로토콜
│   ├── LocalSTTEngine.swift # Qwen3-ASR 온디바이스 엔진
│   └── CloudSTTEngine.swift # 클라우드 API 엔진
├── Hotkey/
│   └── HotkeyManager.swift  # 글로벌 핫키 관리
├── History/
│   └── TranscriptHistory*   # 변환 기록 저장
├── Security/
│   └── KeychainManager.swift # API 키 안전 저장
└── Views/
    ├── MenuBarView.swift     # 메뉴바 UI
    ├── SettingsView.swift    # 설정 화면
    └── RecordingOverlay.swift # 녹음 오버레이
```

---

## Contributing

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Made with ❤️ for macOS**

</div>
