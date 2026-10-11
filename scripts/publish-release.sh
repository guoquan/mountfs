#!/bin/bash
set -euo pipefail
VERSION=$(bash mountfs.sh --version)
BUILD=$(python3 -c 'import plistlib; print(plistlib.load(open("scripts/Info.plist", "rb"))["CFBundleVersion"])')
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[0-9]+$ ]]
TAG="v$VERSION-build.$BUILD"
# Re-running an unchanged version must never replace a published binary.
if gh release view "$TAG" >/dev/null 2>&1; then
    printf 'Release %s already exists; keeping its original assets.\n' "$TAG"
    exit 0
fi
shopt -s nullglob
assets=(release-assets/mouNTFS-"$VERSION"-dev-*.zip)
[ "${#assets[@]}" -gt 0 ] || { printf 'No app archive was downloaded.\n' >&2; exit 1; }
(cd release-assets && sha256sum mouNTFS-"$VERSION"-dev-*.zip > SHA256SUMS.txt)
cat > release-assets/NOTES.md <<EOF
mouNTFS $VERSION — development build $BUILD

Download the application ZIP under Assets, extract it once, quit the old app and move mouNTFS.app into /Applications.

- Requires macOS 13+, macFUSE and ntfs-3g. Use the archive matching your Mac architecture; arm64 means Apple Silicon.
- Ad-hoc signed development build, not Apple-notarized. Hardware/driver compatibility still requires real-Mac testing.
- Check docs/AUTHORIZATION.md for helper availability; build 19 temporarily pauses permission helper and Touch ID in the GUI.
- SHA256SUMS.txt contains the application archive checksums.
- Source commit: $GITHUB_SHA

下载 Assets 中匹配 Mac 架构的应用 ZIP，解压后将 mouNTFS.app 放入 /Applications；更新前先退出旧应用。arm64 为 Apple Silicon。
这是临时签名、未公证的开发构建。需要 macOS 13+、macFUSE 和 ntfs-3g。助手可用状态见 docs/AUTHORIZATION.md；构建 19 暂时关闭权限助手与 Touch ID 界面功能，挂载使用管理员授权。
EOF
# Upload everything as a draft, then make the complete release visible as latest.
gh release create "$TAG" "${assets[@]}" release-assets/SHA256SUMS.txt \
    --target "$GITHUB_SHA" --title "mouNTFS $VERSION (build $BUILD · development)" \
    --notes-file release-assets/NOTES.md --draft
gh release edit "$TAG" --draft=false --latest
