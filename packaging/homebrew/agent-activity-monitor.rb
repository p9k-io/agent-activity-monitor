# The cask for the tap p9k-io/homebrew-tap. It is kept here until the first release is
# published; scripts/release.sh prints the checksum to put in.
cask "agent-activity-monitor" do
  version "0.1.0"
  sha256 :no_check # replaced by the checksum of the released disk image

  url "https://github.com/p9k-io/agent-activity-monitor/releases/download/v#{version}/Agent-Activity-Monitor-#{version}.dmg"
  name "Agent Activity Monitor"
  desc "Shows which processes exist because of AI coding agent sessions"
  homepage "https://github.com/p9k-io/agent-activity-monitor"

  auto_updates true
  depends_on macos: ">= :tahoe"
  depends_on arch: :arm64

  app "Agent Activity Monitor.app"
  binary "#{appdir}/Agent Activity Monitor.app/Contents/Helpers/aam"

  zap trash: [
    "~/Library/Application Support/io.p9k.agent-activity-monitor",
    "~/Library/Preferences/io.p9k.agent-activity-monitor.plist",
  ]
end
