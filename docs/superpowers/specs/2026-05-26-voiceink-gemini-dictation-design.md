# VoiceInk → Typeless 대체: Gemini 한 콜 배치 받아쓰기

- 작성일: 2026-05-26
- 상태: 설계 승인 대기
- 대상 저장소: `/Users/genie/dev/side/VoiceInk` (기존 VoiceInk 포크 위에 구축)

## 1. 목표와 배경

Typeless(유료 SaaS 받아쓰기 앱)를 완전히 대체하는 오픈소스 macOS 메뉴바 앱을 만든다. 단순 전사가 아니라, 주저리주저리 말한 내용을 **군더더기 제거 + 말 중간 정정(최종 의도만) + 깔끔한 불렛/번호 정리**로 가공해 AI 에이전트 프롬프트로 바로 붙여넣기 좋게 만든다.

핵심 제약:

- **로컬 모델 미사용.** 클라우드 API만. 최고 품질 + 속도.
- **실시간 불필요.** 전체 녹음 후 일괄(batch) 처리.
- **완전 오픈소스.** 사용자가 자기 API 키만 넣으면 동작. SaaS 백엔드 없음.
- 입력은 한국어 우선. 영어 번역 모드 별도 제공.

### 조사 결론 (요약)

- batch + 한국어에서는 **오디오를 통째로 멀티모달 LLM에 한 번 보내는 방식**이 가장 단순하고 품질도 우수하다. 지연이 무의미해져 스트리밍 2단계의 이점이 사라진다.
- 멀티모달 LLM 중 한국어 오디오를 신뢰성 있게 처리하는 것은 사실상 **Gemini**뿐(실측 비교에서 Claude는 한국어 음절 깨짐, Kimi는 환각). Claude는 오디오 입력 자체를 지원하지 않는다.
- 기본 모델: **Gemini 3 Flash**(빠른 모델 중 한국어 텍스트 품질 1위권, ~$0.003/분, 한 콜로 전사+정리+번역). 이코노미 옵션으로 2.5 Flash-Lite.
- 유일한 약점은 고유명사·숫자 오전사. 이번 범위에서는 감수하고, 필요 시 향후 2단계(전용 STT→LLM)를 추가할 수 있도록 추상화만 깔아 둔다.

## 2. 확정된 결정

| 항목 | 결정 |
|------|------|
| 코드베이스 | 기존 VoiceInk 포크 위에 구축, 자산 최대 재사용 |
| 아키텍처 | Gemini 한 콜 기본 + 교체 가능한 `SpeechPipeline` 추상화 |
| 녹음 방식 | **토글** (⌥Space로 시작, 다시 ⌥Space로 종료) |
| 모드 | ⌥Space = 정리(cleanup), ⇧⌥Space = 영어 번역 |
| 출력 | **정리된 결과만** (원시 전사 노출/저장 안 함) |
| 삽입 | 커서(편집 요소)에 붙여넣기, 없으면 클립보드 복사 모달 |
| 앱 이름/번들ID | **VoiceInk / com.voiceink.app 유지** (Sparkle 피드 유지) |
| 기본 언어 | 한국어 (정리 모드는 원문 언어 유지) |

## 3. 범위 — 무엇을 바꾸나

### 제거

- `STT/LocalSTTEngine.swift` (Qwen3-ASR)
- `STT/CloudSTTEngine.swift` (ElevenLabs WebSocket 스트리밍)
- `STT/STTEngine.swift` 프로토콜
- `STT/ModelConfiguration.swift`의 `STTModelSize`, `STTEngineType`
- `Qwen3Speech`(speech-swift) 패키지 의존성 (`project.yml`, `SettingsView`의 `import Qwen3ASR`)
- 로컬 모델 다운로드 UI (`EngineSettingsTab`)
- hold-to-talk 경로 (토글 전용)

### 재사용 (대부분 그대로)

- `VoiceInkApp.swift` — 메뉴바 + 설정 Scene
- `AppState.swift` — 오케스트레이터 (내부 리팩터)
- `Audio/AudioSessionManager.swift` — 캡처 + Int16 16kHz 변환 + 레벨 (Int16 경로만 사용)
- `Hotkey/HotkeyManager.swift` — 다중 핫키로 일반화
- `TextInput/TextInputService.swift` — AX 포커스 판정 + 모달 폴백 추가
- `Security/KeychainManager.swift` — 서비스 키만 교체
- `History/TranscriptHistoryManager.swift`
- `Views/RecordingOverlay.swift`, `Views/MenuBarView.swift`, `Views/SettingsView.swift`
- `Utilities/SoundPlayer.swift`, `Utilities/AccessibilityHelper.swift`
- `Update/UpdaterManager.swift` (Sparkle)
- `Resources/Info.plist`, `Resources/VoiceInk.entitlements` (sandbox off, mic on — 그대로)

### 신규

- `Pipeline/SpeechPipeline.swift` — 프로토콜 + 입출력 타입
- `Pipeline/GeminiPipeline.swift` — Gemini 한 콜 구현
- `Pipeline/WAVEncoder.swift` — Int16 PCM 버퍼 → WAV(RIFF) 바이트
- `Dictation/DictationMode.swift` — 모드 정의(id, displayName, hotkey, systemPrompt)
- `Dictation/PromptLibrary.swift` — 모드별 시스템 프롬프트 상수
- `Dictation/DictationController.swift` — 녹음 버퍼 누적 + 파이프라인 호출 + 삽입 조율
- `Views/ResultModal.swift` — 커서 없을 때 결과+클립보드 안내 패널 (`ResultModalController`)
- `Gemini`용 모델 선택 enum (`GeminiModel`)

## 4. 아키텍처

### 4.1 추상화

```swift
struct RecordedAudio {
    let pcm16: Data      // 16kHz mono Int16 little-endian
    let sampleRate: Int  // 16000
}

enum DictationMode: String, CaseIterable {
    case cleanup
    case translateToEnglish
    var displayName: String { ... }
    var systemPrompt: String { PromptLibrary.prompt(for: self) }
}

protocol SpeechPipeline {
    /// 오디오를 받아 정리된 텍스트를 반환. 실패 시 throw.
    func process(_ audio: RecordedAudio, mode: DictationMode) async throws -> String
}
```

`GeminiPipeline`만 기본 구현. 향후 `TwoStepPipeline`(전용 STT→LLM)을 추가해도 호출부(`DictationController`)는 변경 불필요.

### 4.2 GeminiPipeline

- WAV 인코딩(`WAVEncoder`) → base64 인라인 데이터 파트
- 엔드포인트: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}`
  - *정확한 모델 ID와 엔드포인트 경로는 구현 시 최신 Google AI(Gemini API) 문서로 재확인* — 모델명이 자주 바뀐다.
- 요청 본문: `system_instruction`(모드 프롬프트) + `contents[].parts`에 `inline_data {mime_type: "audio/wav", data: <base64>}`
- 응답 파싱: `candidates[0].content.parts[0].text` → trim
- `URLSession`을 주입 가능하게 하여 `URLProtocol` 목으로 테스트
- 오류 매핑: HTTP 4xx(키/권한/요청), 5xx(서버), 타임아웃 → `PipelineError`

인라인 오디오 20MB 한도: 16kHz mono Int16 ≈ 32KB/s → 약 10분까지 안전. 그 이상은 이번 범위 밖(녹음 길이 캡으로 단순화, 캡 초과 시 경고).

### 4.3 상태

`STTStatus`(이름 유지 또는 `DictationStatus`로 변경 — 구현 시 결정)를 다음으로 정리:

```
idle / recording / processing / error(String?)
```

`processing` 신규(Gemini 호출 중). 오버레이/메뉴바 아이콘이 이를 반영.

## 5. 데이터 흐름 (토글)

```
① ⌥Space (idle)   → DictationController.start(mode: .cleanup)
② 캡처 시작        → AudioSessionManager(Int16 16kHz) → Data 누적 + 레벨 → 오버레이 "Listening…"
③ ⌥Space (재입력)  → 캡처 중지 → 버퍼→WAV → status=.processing → 오버레이 "Polishing…"
④ Gemini 호출      → pipeline.process(audio, mode) → 정리 텍스트
⑤ 삽입            → TextInputService.insert(text):
                      ├─ 편집 요소 포커스됨 → 클립보드+Cmd+V (transient 태깅, 이전 클립보드 복원)
                      └─ 없음/실패        → ResultModal 표시 (클립보드엔 결과 유지, 복원 안 함)
⑥ 기록 저장        → TranscriptHistoryManager.add(text, mode) → status=.idle
```

- `⇧⌥Space`는 `mode: .translateToEnglish`로 동일 흐름.
- `processing` 중 핫키 입력은 무시.
- 빈/무음/너무 짧은 녹음(예: < 0.3초 또는 무음)은 조용히 무시하고 `.idle` 복귀.

## 6. 핫키 & 모드

`HotkeyManager`를 모드별 다중 등록으로 일반화:

```swift
struct HotkeyBinding { let keyCode: UInt32; let modifiers: UInt32; let mode: DictationMode }
// ⌥Space(kVK_Space, optionKey) → .cleanup
// ⇧⌥Space(kVK_Space, optionKey|shiftKey) → .translateToEnglish
var onHotkey: ((DictationMode) -> Void)?
```

Carbon `RegisterEventHotKey`를 바인딩당 1개씩 등록(`hotKeyID.id`로 구분). 토글이므로 `kEventHotKeyPressed`만 처리.

### 프롬프트 (PromptLibrary)

- **cleanup**: 한국어 받아쓰기 정리. 군더더기/반복/말더듬 제거, 말 중간 방향 전환 시 최종 의도만 남김, 구두점 정리, 목록·단계는 불렛/번호로, AI 프롬프트로 붙여넣기 좋게. **원문 언어 유지.** 머리말·설명 없이 결과 텍스트만 출력.
- **translateToEnglish**: 위 정리 규칙 + 결과를 자연스러운 영어로 번역해 출력.

향후 사용자 커스텀 모드·개인 사전은 확장 포인트로만 남기고 이번 범위에서는 미구현(YAGNI).

## 7. 텍스트 삽입 + 모달 폴백

`TextInputService` 확장:

```swift
enum InsertResult { case pasted, copiedToClipboard }
@discardableResult func insert(_ text: String) -> InsertResult
```

1. `AXUIElementCreateSystemWide()` → `kAXFocusedUIElementAttribute` 조회.
2. 편집 가능 판정: role이 `AXTextField/AXTextArea/AXComboBox`이거나 `kAXValueAttribute`가 settable → **클립보드+Cmd+V**(현 코드 재사용). pasteboard를 `org.nspasteboard.TransientType`로 태깅하고, 붙여넣기 후 이전 클립보드 복원.
3. 포커스 요소 없음/판정 실패 → `ResultModalController`로 작은 패널 표시: 결과 텍스트 + "📋 클립보드에 복사됨" + 복사/닫기 버튼. 이때 클립보드엔 결과를 올려두고 **복원하지 않음**(사용자가 직접 붙여넣어야 하므로).

설계 메모: Electron/웹뷰는 AX role을 오보고할 수 있다. 과하게 막지 않고 "편집 요소로 보이면 붙여넣기 시도"가 기본. 붙여넣기 성공 여부의 완전 검증(Wispr 방식)은 복잡하므로 이번엔 **포커스 유무 판정 + 모달 폴백**까지만.

AX 판정 로직은 순수 함수(예: role 문자열 → 편집 가능 여부)로 분리해 단위 테스트.

## 8. 설정 UI

`SettingsView` 탭 재구성:

- **General**: Launch at Login, 핫키 안내(⌥Space=정리, ⇧⌥Space=영어 번역 고정 표시), 업데이트 확인. hold-to-talk 토글 제거.
- **Model**: Gemini 모델 선택(`GeminiModel`: gemini-3-flash / gemini-2.5-flash-lite 등 — 구현 시 최신 ID 확인). 기본 언어 안내.
- **API Key**: ElevenLabs → **Google AI(Gemini) API 키**. `APIKeyService.gemini` 추가, `.elevenLabs` 제거. 안내 문구: "aistudio.google.com에서 발급".

## 9. 에러 처리

- API 키 없음 → 녹음 시작 시 알림(`showErrorAlert` 재사용, "Open Settings" 버튼으로 API Key 탭 이동).
- 빈/무음 녹음 → 조용히 무시.
- 네트워크/API 오류(4xx/5xx/타임아웃) → 오버레이 또는 알림에 메시지 표시, 클립보드 변경 없음, 원본 클립보드 보존.
- 녹음 길이 캡(기본 10분) 초과 → 자동 종료 + 경고.

## 10. 테스트

- `WAVEncoder`: RIFF 헤더 바이트(샘플레이트/채널/비트/데이터 길이) 단위 검증.
- `GeminiPipeline`: `URLProtocol` 목으로 (a) 요청 본문에 system_instruction·오디오 파트 포함, (b) 정상 응답 파싱, (c) 4xx/5xx/타임아웃 → 올바른 `PipelineError` 매핑.
- `PromptLibrary`/`DictationMode`: 모드 → 프롬프트 매핑.
- `TextInputService`: AX role → 편집 가능 판정 순수 함수. 실제 CGEvent 붙여넣기·모달은 수동 통합 테스트(체크리스트).

## 11. 마일스톤(개략)

1. 의존성/엔진 제거 + 빌드 통과(스텁 파이프라인).
2. `WAVEncoder` + `SpeechPipeline`/`GeminiPipeline` + 테스트.
3. `DictationController` + `AppState` 리팩터(토글, processing 상태).
4. 다중 핫키(`HotkeyManager`) + `DictationMode`/`PromptLibrary`.
5. `TextInputService` AX 판정 + `ResultModal` 폴백.
6. 설정 UI 재구성 + `APIKeyService.gemini`.
7. 수동 통합 검증(실제 한국어 발화 5~10건), 고유명사 케이스 관찰.

## 12. 비목표 (이번 범위 밖)

- 실시간/스트리밍 전사, 라이브 부분 자막.
- 2단계 파이프라인(전용 STT→LLM), 멀티 벤더 선택 UI (추상화만 마련).
- 사용자 커스텀 모드/프롬프트 편집, 개인 사전, per-app 자동 모드 전환.
- 원시 전사 노출/저장.
- 앱 리네임.
