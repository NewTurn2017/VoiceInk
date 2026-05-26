<div align="center">

<img src="docs/assets/icon.png" width="128" alt="VoiceInk" />

# VoiceInk

**말하면 — 정리된 텍스트로. Gemini 기반 macOS 받아쓰기**

[![Download](https://img.shields.io/badge/Download-DMG-blue?logo=apple&logoColor=white&style=for-the-badge)](https://github.com/NewTurn2017/VoiceInk/releases/latest/download/VoiceInk.dmg)

[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple&logoColor=white)](#requirements)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## What is VoiceInk?

VoiceInk은 macOS 메뉴바에서 동작하는 **AI 받아쓰기 앱**입니다. 단순 전사가 아니라, 주저리주저리 말한 내용을 **Google Gemini가 한 번에 전사 + 정리**해 줍니다 — 군더더기·반복 제거, 말 중간에 바꾼 내용은 최종 의도만 남기고, 목록은 불렛/번호로 깔끔하게. AI 에이전트에 붙여넣을 프롬프트를 말로 부르기에 최적입니다.

단축키 하나로 녹음하고, 결과는 **현재 커서 위치에 바로 입력**됩니다. 완전 오픈소스이며 **본인의 Gemini API 키만 넣으면** 동작합니다(별도 SaaS·구독 없음).

### Key Features

- **AI 정리 받아쓰기** — Gemini로 전사하며 군더더기 제거, 말 중간 정정 해소, 불렛/번호 포맷팅까지 한 번에
- **두 가지 모드** — `⌥ Space` 정리 받아쓰기 · `⇧ ⌥ Space` 영어로 번역
- **커서에 바로 삽입** — 포커스된 입력란이 없으면 클립보드 복사 + 유리(글래스) 결과 모달로 폴백
- **메탈릭 리퀴드 글래스 UI** — 녹음 중 파형, 처리 중 "Thinking" 오버레이 (macOS 26에서 Liquid Glass)
- **무음 자동 취소** — 말하지 않으면 API 호출 없이 즉시 종료
- **실시간 API 비용 추적** — 설정에서 사용 토큰·예상 비용 확인
- **변환 기록** — 최근 받아쓰기 기록 저장
- **메뉴바 앱** — Dock에 안 뜨는 가벼운 백그라운드 앱
- **Bring your own key** — 오픈소스, Gemini 키만 있으면 사용

---

## Download

> **[⬇︎ VoiceInk.dmg 최신 버전 다운로드](https://github.com/NewTurn2017/VoiceInk/releases/latest/download/VoiceInk.dmg)** · [모든 릴리스 보기](https://github.com/NewTurn2017/VoiceInk/releases)

1. DMG를 열고 **VoiceInk을 Applications 폴더로 드래그**합니다.
2. 처음 실행 시 **마이크**와 **손쉬운 사용(Accessibility)** 권한을 허용하세요. 접근성은 커서 위치 입력에 필요하며, 켠 뒤 앱을 한 번 재시작합니다(메뉴 → Restart VoiceInk).
3. **설정 → API Key** 에 Google AI(Gemini) 키를 입력합니다. 키는 [aistudio.google.com](https://aistudio.google.com) → API keys에서 무료로 발급할 수 있습니다.

### Build from Source

```bash
git clone https://github.com/NewTurn2017/VoiceInk.git
cd VoiceInk
xcodegen generate     # project.yml → VoiceInk.xcodeproj
open VoiceInk.xcodeproj
# Xcode에서 ⌘R 로 빌드 및 실행
```

---

## Quick Start

1. VoiceInk을 실행하면 메뉴바에 마이크 아이콘이 나타납니다.
2. **`⌥ Space`** 를 눌러 녹음을 시작하고, 말을 마치면 다시 **`⌥ Space`** 를 눌러 종료합니다(토글).
3. 잠깐의 "Thinking" 후, **정리된 텍스트가 커서 위치에 입력**됩니다.
4. 영어로 옮기고 싶으면 **`⇧ ⌥ Space`** 로 같은 흐름을 쓰면 됩니다.

### Settings

메뉴바 아이콘 → **Settings**:

- **Model** — Gemini 모델 선택 (`gemini-3.5-flash` 권장 · `gemini-2.5-flash` 이코노미)
- **API Key** — Google AI(Gemini) 키 입력
- **Usage** — 누적 사용 토큰과 예상 API 비용 실시간 표시
- **Permissions** — 접근성/마이크 권한 상태 확인 및 재시작

---

## Cost

오디오 입력은 비용의 대부분을 차지하며, 사실상 **말한 시간 = 비용**입니다(추론 off). ~100단어(약 13초) 받아쓰기 1회 기준 대략:

| 모델 | 회당 | $1당 |
|------|------|------|
| `gemini-2.5-flash` | ~$0.0006 | ~1,800회 |
| `gemini-3.5-flash` | ~$0.0009 | ~1,100회 |

설정의 **Usage** 탭에서 실제 응답 토큰 기반 누적 비용을 확인할 수 있습니다.

---

## Privacy

녹음된 오디오는 전사·정리를 위해 **Google Gemini API로 전송**됩니다. API 키는 macOS **키체인**에 안전하게 저장됩니다. 받아쓰기 내용이 학습에 쓰이지 않도록 하려면 무료 티어 대신 **결제(유료) 티어** 사용을 권장합니다.

---

## Architecture

```
VoiceInk/
├── AppState.swift              # 앱 상태 오케스트레이터 (@MainActor)
├── Pipeline/
│   ├── SpeechPipeline.swift    # 교체 가능한 파이프라인 프로토콜 + 타입
│   ├── GeminiPipeline.swift    # Gemini 한-콜 전사+정리 구현
│   └── WAVEncoder.swift        # 16kHz mono PCM → WAV
├── Dictation/
│   ├── DictationController.swift # 녹음 → 파이프라인 → 삽입 조율
│   ├── DictationMode.swift     # cleanup / translateToEnglish
│   └── PromptLibrary.swift     # 모드별 시스템 프롬프트
├── Audio/AudioSessionManager.swift # 캡처·누적·레벨
├── Hotkey/HotkeyManager.swift  # 모드별 글로벌 핫키
├── TextInput/TextInputService.swift # 커서 삽입(AX) + 클립보드 폴백
├── CostTracker.swift           # 토큰/비용 누적
├── Security/KeychainManager.swift   # API 키 저장
└── Views/                      # 메뉴바 · 설정 · 글래스 오버레이 · 결과 모달
```

---

## Requirements

| 항목 | 요구 사항 |
|------|-----------|
| macOS | 14.0 (Sonoma) 이상 · Liquid Glass UI는 macOS 26+ |
| 네트워크 | 필요 (Gemini API 호출) |
| API 키 | Google AI(Gemini) 키 |
| Xcode | 빌드 시 26 (SwiftUI `glassEffect`) |

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
