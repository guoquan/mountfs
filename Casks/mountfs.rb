cask "mountfs" do
  version "0.3.5,20"
  sha256 "35be4cb65bab0c1f90c6b8b16f4e281873be16588ec97ff890c92dbf15a2edab"

  url "https://github.com/guoquan/mountfs/releases/download/v0.3.5-build.20/mouNTFS-0.3.5-dev-arm64.zip"
  name "mouNTFS"
  desc "Menu bar app for writing to external NTFS drives"
  homepage "https://mountfs.app/"

  depends_on arch: :arm64
  depends_on cask: "macfuse"
  depends_on macos: ">= :ventura"

  app "mouNTFS.app"

  caveats <<~EOS
    This is an ad-hoc signed, unnotarized development build for Apple Silicon.
    macOS may block first launch. Homebrew does not bypass Gatekeeper.
    Install the third-party NTFS driver separately:
      brew install gromgit/fuse/ntfs-3g-mac
    Follow macFUSE's system approval and restart instructions.
    Quit mouNTFS before upgrading. Eject active NTFS mounts before uninstalling.
    Disable any previously registered permission helper in app Settings first.
    See https://github.com/guoquan/mountfs/blob/main/docs/HOMEBREW.md
  EOS
end
