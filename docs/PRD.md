# PRD: VoiceInk — macOS Background STT App

**Version**: 1.0
**Date**: 2026-03-23
**Author**: genie + Claude
**Status**: Confirmed

---

## 1. Executive Summary

**VoiceInk**는 macOS에서 커서가 있는 어디든 음성으로 텍스트를 입력할 수 있는 메뉴바 앱이다.
로컬 AI 모델(Qwen3-ASR-1.7B)을 기본 엔진으로 사용하여 인터넷 없이도 한국어 음성 인식이 가능하며,
ElevenLabs 클라우드 엔진을 선택적으로 사용할 수 있다.

**핵심 가치**: 인터넷 없이, 어디서든, 말하면 타이핑되는 앱.

| 항목 | 내용 |
|------|------|
| Feature | VoiceInk — 프로덕션급 macOS STT 앱 |
| Target | 개인 사용 (직접 배포, Notarized DMG) |
| Duration | Phase 1~4, 약 4 Phase 구현 |
| Core Value | 로컬 AI STT로 프라이버시 보장 + 오프라인 사용 |

### Confirmed Decisions
| 결정 사항 | 내용 |
|-----------|------|
| 앱 이름 | **VoiceInk** |
| 번들 ID | `com.voiceink.app` |
| 최소 macOS | **14.0+** (Sonoma) |
| 기본 모델 | **Qwen3-ASR-1.7B** (정확도 우선, WER 2.57%) |
| 모델 배포 | 첫 실행 시 다운로드 (~3.4GB fp16, ~1.7GB 8bit) |
| 코드 서명 | Developer ID Application: jaehyun jang (2UANJX7ATM) |
| Team ID | 2UANJX7ATM |

---

## 2. Problem Statement

### 현재 상태 (VoiceType v0.1)
- ElevenLabs 클라우드 API에 100% 의존 (오프라인 불가)
- API 키가 소스코드에 하드코딩 (보안 위험)
- 마이크 인식 불안정 (재연결 로직 없음)
- 빌드 스크립트 수동, 공증/서명 없음
- 아이콘/UI가 프로토타입 수준

### 목표 상태 (VoiceType Pro v1.0)
- 로컬 STT 엔진 기본 탑재 (오프라인 동작)
- 클라우드 엔진 선택적 사용 (설정에서 전환)
- 안정적 마이크 처리 + 자동 재연결
- Apple Developer ID 서명 + Notarization
- 정식 아이콘 + 세련된 UI

---

## 3. Goals & Metrics

| Priority | Goal | Success Metric |
|----------|------|----------------|
| **P0** | 로컬 STT 엔진 통합 (Qwen3-ASR) | 한국어 WER < 5%, 오프라인 동작 |
| **P0** | 마이크 안정성 개선 | 연속 1시간 녹음 시 끊김 0회 |
| **P0** | API 키 보안 처리 | 소스코드에 키 제로, 설정 UI에서 입력 |
| **P1** | 설정 UI (엔진 선택, 키 입력) | 설정 창에서 엔진 전환 가능 |
| **P1** | Notarization + DMG 배포 | 경고 없이 설치/실행 |
| **P1** | 정식 아이콘 + 다중 크기 | 16~1024px, .icns 포함 |
| **P2** | 앱 이름 리브랜딩 | 새 이름 + 번들 ID 반영 |
| **P2** | UI 개선 (메뉴바 + 설정 창) | 상태 표시 명확, 시각적 피드백 |

---

## 4. Non-Goals

- Mac App Store 배포 (직접 배포로 한정)
- iOS/iPadOS 지원
- 다국어 UI (한국어 단일)
- 실시간 자막/오버레이 UI
- 유료화/라이선스 관리
- Apple SpeechAnalyzer 통합 (macOS 26 전용, 향후 고려)

---

## 5. User Persona

### Persona: genie (개인 개발자)
- macOS Apple Silicon 사용자
- 한국어가 주 언어, 영어 혼용
- 다양한 앱(IDE, 브라우저, 메신저)에서 음성 입력 필요
- 프라이버시 중시 — 음성 데이터가 외부로 나가지 않길 원함
- 오프라인 환경에서도 사용 필요 (카페, 비행기 등)

---

## 6. Technical Research Summary

### 6.1 STT 엔진 비교

| 엔진 | 한국어 WER | 실시간 | 오프라인 | Swift 통합 | 메모리 |
|------|-----------|--------|---------|-----------|--------|
| **Qwen3-ASR-0.6B** (MLX) | 3.72% | RTF 0.03 | O | speech-swift (SPM) | 0.7GB (8bit) |
| **Qwen3-ASR-1.7B** (MLX) | **2.57%** | RTF 0.27 | O | speech-swift (SPM) | 3.4GB (fp16) |
| ElevenLabs Scribe v2 | 미공개 (체감 우수) | O | X (클라우드) | WebSocket | 0 (서버측) |
| WhisperKit (large-v3) | ~5-7% | RTF 0.1 | O | SPM native | ~3.9GB |
| Whisper-turbo-korean | 4.89% | RTF 0.15 | O | SwiftWhisper | ~2.1GB |
| Apple SpeechAnalyzer | 미공개 | O | O | Native | 0 (시스템) |

### 6.2 권장 엔진 구성

```
[기본] Qwen3-ASR-0.6B (MLX/CoreML, speech-swift)
  - 오프라인 동작, 빠른 속도, 낮은 메모리
  - 한국어 WER 3.72% (충분히 실용적)

[선택] ElevenLabs Scribe v2 (클라우드)
  - 기존 구현 유지, 사용자 API 키 입력 방식
  - 인터넷 필요, 더 긴 문맥 처리에 유리

[향후] Qwen3-ASR-1.7B 옵션 추가
  - 더 높은 정확도 필요 시 (WER 2.57%)
  - 메모리 3.4GB 필요
```

### 6.3 Swift 통합 경로

**speech-swift** 패키지 (`soniqo/speech-swift`):
- Swift Package Manager 지원
- MLX Swift + CoreML 하이브리드 (Metal GPU + Neural Engine)
- macOS 14+, Apple Silicon
- `Qwen3ASR` 모듈 import

```swift
// Package.swift
.package(url: "https://github.com/soniqo/speech-swift", branch: "main")
```

**대안 (HTTP 서버 방식)**:
```bash
pip install "mlx-qwen3-asr[serve]"
mlx-qwen3-asr --serve  # localhost OpenAI-compatible API
```
Swift에서 URLSession으로 호출 — 모델 교체가 자유롭지만 Python 의존성 발생.

### 6.4 Notarization 요구사항

- Apple Developer ID 서명 필수
- Hardened Runtime 활성화 (`-o runtime`)
- ML 모델은 데이터 파일 → 특별한 entitlement 불필요
- 모델 파일은 앱 번들에 포함하거나, 첫 실행 시 다운로드 (WhisperKit 패턴)

**필요 Entitlements:**
```xml
<key>com.apple.security.device.audio-input</key><true/>
```

---

## 7. Functional Requirements

### FR-001: STT 엔진 추상화 레이어
- `STTEngine` 프로토콜 정의 (start, stop, onTranscript, onStatus)
- `LocalSTTEngine` (Qwen3-ASR) + `CloudSTTEngine` (ElevenLabs) 구현
- 설정에서 엔진 전환 시 즉시 반영

### FR-002: 로컬 STT 엔진 (Qwen3-ASR)
- speech-swift 패키지를 통한 Qwen3-ASR-0.6B 통합
- AVAudioEngine → PCM 16kHz 변환 → Qwen3ASR 추론
- 첫 실행 시 모델 자동 다운로드 (~400MB, 8bit)
- 진행률 표시 (다운로드 중)

### FR-003: 클라우드 STT 엔진 (ElevenLabs)
- 기존 WebSocket 구현 유지
- API 키를 Keychain에 저장 (하드코딩 제거)
- 설정 UI에서 키 입력/수정/삭제

### FR-004: 마이크 안정성 개선
- WebSocket/오디오 엔진 연결 끊김 시 자동 재연결 (최대 3회)
- 오디오 세션 인터럽트 처리 (다른 앱이 마이크 점유 시)
- 마이크 장치 변경 감지 + 자동 전환
- 녹음 시작/중지 시 debounce 유지 (500ms)

### FR-005: 설정 UI (Preferences Window)
- NSWindow 기반 설정 창 (메뉴바 > "설정..." 클릭)
- 탭 구성:
  - **일반**: 로그인 시 자동 시작, 글로벌 핫키 변경
  - **엔진**: 로컬/클라우드 선택, 모델 크기 선택 (0.6B/1.7B)
  - **ElevenLabs**: API 키 입력, 연결 테스트
- UserDefaults로 설정 저장

### FR-006: API 키 보안
- 소스코드에서 모든 하드코딩 키 제거
- macOS Keychain Services로 API 키 저장/조회
- 환경변수 `ELEVENLABS_API_KEY` 폴백 유지

### FR-007: 앱 아이콘 (Production-grade)
- 다중 크기 생성: 16, 32, 64, 128, 256, 512, 1024px + @2x
- .icns 파일 생성 및 번들 포함
- 메뉴바 아이콘: 16x16 @2x 템플릿 이미지
- 마이크 + 음파 모티프의 미니멀 디자인

### FR-008: 빌드 & 배포 파이프라인
- `build.sh` 개선: 서명 + Notarization 자동화
- Developer ID Application 인증서로 코드 서명
- `xcrun notarytool submit` 으로 공증
- DMG 또는 zip 배포 패키지 생성

### FR-009: 앱 리브랜딩
- 앱 이름: **VoiceInk** (확정)
- 번들 ID: `com.voiceink.app`
- CFBundleName / CFBundleDisplayName 업데이트
- 모든 소스코드 내 "VoiceType" 참조 일괄 변경

### FR-010: 텍스트 입력 안정성
- 클립보드 복원 실패 시 폴백 처리
- 긴 텍스트 입력 시 청크 분할 (1000자 단위)
- Accessibility 권한 미부여 시 명확한 안내 다이얼로그

---

## 8. Implementation Phases

### Phase 1: 아키텍처 리팩토링 + 보안 (기반)
> 엔진 추상화, API 키 보안, 마이크 안정성

1. `STTEngine` 프로토콜 정의
2. 기존 `STTManager` → `CloudSTTEngine` (ElevenLabs) 리팩토링
3. API 키 Keychain 저장 구현
4. 소스코드 하드코딩 키 제거
5. 마이크 자동 재연결 로직 추가
6. 오디오 세션 인터럽트 핸들링

**의존성**: 없음 (기존 코드 리팩토링)

### Phase 2: 로컬 STT 엔진 통합
> Qwen3-ASR via speech-swift

1. speech-swift 패키지 추가 (SPM)
2. `LocalSTTEngine` 구현 (Qwen3ASR 모듈)
3. 모델 다운로드 매니저 (첫 실행 시)
4. AVAudioEngine → Qwen3ASR 파이프라인
5. 엔진 전환 로직 (Local ↔ Cloud)
6. 로컬 엔진 한국어 테스트 + 벤치마크

**의존성**: Phase 1 (STTEngine 프로토콜)

### Phase 3: UI + 설정 + 리브랜딩
> 설정 창, 아이콘, 앱 이름

1. 앱 이름 확정 + 번들 ID 변경
2. 정식 앱 아이콘 디자인 + .icns 생성
3. 메뉴바 템플릿 아이콘 제작
4. Preferences 창 구현 (일반/엔진/API 키 탭)
5. 메뉴바 메뉴 개선 (상태 표시, 설정 접근)
6. 시각적 피드백 개선 (녹음 중 애니메이션 등)

**의존성**: Phase 1 (키 관리), Phase 2 (엔진 선택 UI)

### Phase 4: 배포 준비
> 서명, 공증, DMG 패키지

1. Apple Developer ID 인증서 설정
2. Entitlements 파일 작성
3. Hardened Runtime 빌드 설정
4. 코드 서명 자동화 (build.sh)
5. Notarization 자동화 (notarytool)
6. DMG 패키지 생성 스크립트
7. README + 설치 가이드 작성

**의존성**: Phase 3 (최종 앱 이름/아이콘)

---

## 9. Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|------------|------------|
| speech-swift가 불안정하거나 macOS 13 미지원 | 높음 | 중간 | HTTP 서버 방식(mlx-qwen3-asr --serve) 폴백, 또는 WhisperKit 대안 |
| Qwen3-ASR 0.6B 한국어 정확도가 체감상 부족 | 중간 | 낮음 | 1.7B 모델 옵션 제공, 또는 한국어 파인튜닝 Whisper 대안 |
| 모델 다운로드 크기 (~400MB)가 UX에 부정적 | 낮음 | 낮음 | 진행률 표시 + 백그라운드 다운로드 |
| Apple Developer ID 미보유 | 높음 | 확인필요 | $99/년 Apple Developer Program 가입 필요 |
| Carbon Events API 향후 제거 | 중간 | 낮음 | NSEvent.addGlobalMonitorForEvents 대안 준비 |
| 모델 라이선스 이슈 | 낮음 | 낮음 | Qwen3-ASR Apache 2.0 — 상업적 사용 무제한 |

---

## 10. Open Questions (Resolved)

| 질문 | 결정 |
|------|------|
| 앱 이름 | **VoiceInk** |
| Apple Developer ID | 보유 — jaehyun jang (2UANJX7ATM) |
| 최소 macOS | **14.0+** (speech-swift 요구사항 충족) |
| 모델 배포 | 첫 실행 시 다운로드 |
| 기본 모델 | **1.7B** (정확도 우선) |

### Remaining Questions
1. **speech-swift 실제 통합 테스트**: 패키지 resolve + 빌드 성공 여부 확인 필요
2. **1.7B 8bit 양자화**: fp16 (3.4GB) vs 8bit (~1.7GB) 중 기본값 결정

---

## Appendix: Reference Projects

| Project | URL | 용도 |
|---------|-----|------|
| speech-swift (Qwen3-ASR Swift) | github.com/soniqo/speech-swift | 로컬 STT 엔진 |
| mlx-qwen3-asr | github.com/moona3k/mlx-qwen3-asr | MLX 벤치마크/서버 |
| WhisperKit | github.com/argmaxinc/WhisperKit | 대안 로컬 엔진 |
| AudioWhisper | github.com/mazdak/AudioWhisper | 메뉴바 앱 참고 |
| Typester | github.com/nickustinov/typester-macos | 텍스트 입력 참고 |
| SwiftWhisper | github.com/exPHAT/SwiftWhisper | whisper.cpp Swift 래퍼 |
