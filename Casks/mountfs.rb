cask "mountfs" do
  version "0.3.4,19"
  sha256 "46186804b0c7464f2e1138d95df177cba987d41b8f5c976de250a74a3d8ea5c2"

  url "https://github.com/guoquan/mountfs/releases/download/v0.3.4-build.19/mouNTFS-0.3.4-dev-arm64.zip"
  name "mouNTFS"
  desc "Menu bar app for writing to external NTFS drives"
  homepage "https://mountfs.sh/"

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
