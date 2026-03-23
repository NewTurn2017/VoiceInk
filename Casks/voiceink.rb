cask "voiceink" do
  version :latest
  sha256 :no_check

  url "https://github.com/NewTurn2017/VoiceInk/releases/latest/download/VoiceInk-#{version}.dmg"
  name "VoiceInk"
  desc "Voice-to-text input tool for macOS"
  homepage "https://github.com/NewTurn2017/VoiceInk"

  depends_on macos: ">= :sonoma"

  app "VoiceInk.app"

  zap trash: [
    "~/Library/Preferences/com.voiceink.app.plist",
    "~/Library/Application Support/VoiceInk",
  ]
end
