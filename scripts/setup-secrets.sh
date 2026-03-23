#!/bin/bash
set -euo pipefail

# ============================================================
#  VoiceInk — GitHub Secrets 자동 설정 스크립트
#
#  사용법:
#    ./scripts/setup-secrets.sh
#
#  사전 준비:
#    1. gh CLI 로그인:  gh auth login
#    2. Developer ID Application 인증서가 Keychain에 설치되어 있어야 함
#    3. App-Specific Password 생성: https://appleid.apple.com → 앱 암호
# ============================================================

REPO="NewTurn2017/VoiceInk"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VoiceInk GitHub Secrets 설정"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- gh CLI 확인 ---
if ! command -v gh &>/dev/null; then
  echo "❌ gh CLI가 설치되어 있지 않습니다."
  echo "   brew install gh && gh auth login"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "❌ gh CLI에 로그인되어 있지 않습니다."
  echo "   gh auth login 을 먼저 실행하세요."
  exit 1
fi

echo "✅ gh CLI 인증 확인됨"
echo ""

# ─── 1. Developer ID Application 인증서 (p12) ───
echo "━━━ Step 1/5: Developer ID Application 인증서 ━━━"
echo ""
echo "📋 Keychain Access에서 인증서를 내보내는 방법:"
echo "   1. Keychain Access 앱 열기"
echo "   2. '내 인증서' 탭 선택"
echo "   3. 'Developer ID Application: ...' 인증서 우클릭"
echo "   4. '내보내기' → .p12 형식으로 저장"
echo "   5. 내보내기 비밀번호 설정 (아래에서 입력)"
echo ""
read -rp "p12 파일 경로 (드래그 앤 드롭 가능): " P12_PATH

# 따옴표/공백 정리
P12_PATH=$(echo "$P12_PATH" | sed "s/^['\"]//;s/['\"]$//;s/^ //;s/ $//")

if [ ! -f "$P12_PATH" ]; then
  echo "❌ 파일을 찾을 수 없습니다: $P12_PATH"
  exit 1
fi

# base64 인코딩 후 시크릿 설정
P12_BASE64=$(base64 -i "$P12_PATH")
if [ -z "$P12_BASE64" ]; then
  echo "❌ p12 파일 base64 인코딩 실패"
  exit 1
fi
gh secret set CERTIFICATE_P12 --body "$P12_BASE64" --repo="$REPO"
echo "✅ CERTIFICATE_P12 설정 완료"
echo ""

# ─── 2. 인증서 비밀번호 ───
echo "━━━ Step 2/5: 인증서 내보내기 비밀번호 ━━━"
echo ""
read -rsp "p12 내보내기 시 설정한 비밀번호: " CERT_PASSWORD
echo ""
if [ -z "$CERT_PASSWORD" ]; then
  echo "❌ 비밀번호가 비어있습니다."
  exit 1
fi
gh secret set CERTIFICATE_PASSWORD --body "$CERT_PASSWORD" --repo="$REPO"
echo "✅ CERTIFICATE_PASSWORD 설정 완료"
echo ""

# ─── 3. Apple ID ───
echo "━━━ Step 3/5: Apple ID (공증용) ━━━"
echo ""
read -rp "Apple Developer 계정 이메일: " APPLE_ID
if [ -z "$APPLE_ID" ]; then
  echo "❌ Apple ID가 비어있습니다."
  exit 1
fi
gh secret set APPLE_ID --body "$APPLE_ID" --repo="$REPO"
echo "✅ APPLE_ID 설정 완료"
echo ""

# ─── 4. App-Specific Password ───
echo "━━━ Step 4/5: App-Specific Password ━━━"
echo ""
echo "📋 생성 방법:"
echo "   1. https://appleid.apple.com 접속"
echo "   2. 로그인 → '앱 암호' (App Passwords)"
echo "   3. '+' 클릭 → 이름: 'VoiceInk Notarization'"
echo "   4. 생성된 비밀번호 복사 (xxxx-xxxx-xxxx-xxxx 형식)"
echo ""
read -rsp "App-Specific Password: " APP_PASSWORD
echo ""
if [ -z "$APP_PASSWORD" ]; then
  echo "❌ App-Specific Password가 비어있습니다."
  exit 1
fi
gh secret set APPLE_ID_PASSWORD --body "$APP_PASSWORD" --repo="$REPO"
echo "✅ APPLE_ID_PASSWORD 설정 완료"
echo ""

# ─── 5. Team ID ───
echo "━━━ Step 5/5: Apple Team ID ━━━"
echo ""
TEAM_ID="2UANJX7ATM"
read -rp "Team ID [$TEAM_ID]: " INPUT_TEAM_ID
TEAM_ID="${INPUT_TEAM_ID:-$TEAM_ID}"
gh secret set APPLE_TEAM_ID --body "$TEAM_ID" --repo="$REPO"
echo "✅ APPLE_TEAM_ID 설정 완료"
echo ""

# ─── 확인 ───
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  모든 시크릿이 설정되었습니다!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  설정된 시크릿:"
gh secret list --repo="$REPO"
echo ""
echo "  다음 단계:"
echo "    git tag v1.0.0 && git push origin v1.0.0"
echo "    → GitHub Actions가 자동으로 빌드 + 공증 + 릴리스 생성"
echo ""
