class Cmdspeak < Formula
  desc "Drop-in replacement for macOS Dictation with OpenAI streaming transcription"
  homepage "https://github.com/LxYuan0420/cmdspeak"
  url "https://github.com/LxYuan0420/cmdspeak.git", tag: "v0.3.0"
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

      Set your OpenAI API key:
        export OPENAI_API_KEY=your-key

      Usage:
        cmdspeak              # Start dictation (double-tap Right Option)
        cmdspeak setup        # Configure permissions
    EOS
  end

  test do
    assert_match "CmdSpeak", shell_output("#{bin}/cmdspeak --version")
  end
end
