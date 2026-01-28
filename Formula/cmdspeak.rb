class Cmdspeak < Formula
  desc "Drop-in replacement for macOS Dictation with local and cloud transcription"
  homepage "https://github.com/LxYuan0420/cmdspeak"
  url "https://github.com/LxYuan0420/cmdspeak.git", tag: "v0.1.0"
  license "MIT"
  head "https://github.com/LxYuan0420/cmdspeak.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos => :sonoma

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/cmdspeak"
  end

  def caveats
    <<~EOS
      CmdSpeak requires Accessibility and Microphone permissions.

      To grant permissions:
        System Settings → Privacy & Security → Accessibility → Add cmdspeak
        System Settings → Privacy & Security → Microphone → Add cmdspeak

      Disable macOS Dictation to avoid conflicts:
        System Settings → Keyboard → Dictation → Shortcut → Off

      Usage:
        cmdspeak run          # Run with local WhisperKit (default)
        cmdspeak run-openai   # Run with OpenAI (requires OPENAI_API_KEY)

      First run downloads ~1GB model and compiles for Neural Engine (2-4 min).
    EOS
  end

  test do
    assert_match "CmdSpeak", shell_output("#{bin}/cmdspeak --version")
  end
end
