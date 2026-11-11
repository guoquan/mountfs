#!/usr/bin/env python3
"""Render or synchronize the same-repository Homebrew cask from a published Release."""
import base64
import json
import os
from pathlib import Path
import re
import sys
import urllib.request
from urllib.error import HTTPError
from urllib.parse import urlencode

REPO = "guoquan/mountfs"
API = f"https://api.github.com/repos/{REPO}"


def render(release):
    match = re.fullmatch(r"v(\d+\.\d+\.\d+)-build\.(\d+)", release.get("tag_name", ""))
    if not match or release.get("draft") is not False or release.get("prerelease") is not False:
        raise ValueError("Expected a published versioned development release")
    version, build = match.groups()
    name = f"mouNTFS-{version}-dev-arm64.zip"
    assets = [a for a in release.get("assets", []) if a.get("name") == name]
    if len(assets) != 1:
        raise ValueError("Expected exactly one Apple Silicon application archive")
    asset = assets[0]
    digest = re.fullmatch(r"sha256:([0-9a-f]{64})", asset.get("digest", ""))
    url = f"https://github.com/{REPO}/releases/download/{release['tag_name']}/{name}"
    if not digest or asset.get("browser_download_url") != url or asset.get("state") != "uploaded":
        raise ValueError("Release asset URL, upload state or SHA-256 is invalid")
    return f'''cask "mountfs" do
  version "{version},{build}"
  sha256 "{digest.group(1)}"

  url "{url}"
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
'''


def request(path, token, data=None, *, method=None):
    headers = {"Accept": "application/vnd.github+json", "Authorization": f"Bearer {token}"}
    body = json.dumps(data).encode() if data is not None else None
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(API + path, data=body, headers=headers, method=method or ("PUT" if data else "GET"))
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--render":
        print(render(json.loads(Path(sys.argv[2]).read_text())), end="")
        return
    token = os.environ["GH_TOKEN"]
    release = request("/releases/latest", token)
    desired = render(release)
    current = request("/contents/Casks/mountfs.rb?ref=main", token)
    existing = base64.b64decode(current["content"]).decode()
    if existing == desired:
        print("Homebrew cask already matches the latest Release")
        return
    old = re.search(r'version "(\d+)\.(\d+)\.(\d+),(\d+)"', existing)
    new = re.search(r'version "(\d+)\.(\d+)\.(\d+),(\d+)"', desired)
    if not old or tuple(map(int, new.groups())) <= tuple(map(int, old.groups())):
        raise ValueError("Refusing an unchanged-version replacement or release downgrade")
    # main requires a pull request. Never write a release update directly to it.
    branch = f"homebrew/{release['tag_name']}"
    head = request("/git/ref/heads/main", token)["object"]["sha"]
    try:
        request("/git/refs", token, {"ref": f"refs/heads/{branch}", "sha": head}, method="POST")
    except HTTPError as error:
        if error.code != 422:
            raise
        # A retried release may already have created this deterministic branch.
        request(f"/git/ref/heads/{branch}", token)
    pending = request(f"/contents/Casks/mountfs.rb?ref={branch}", token)
    pending_text = base64.b64decode(pending["content"]).decode()
    if pending_text != desired:
        pending_version = re.search(r'version "(\d+)\.(\d+)\.(\d+),(\d+)"', pending_text)
        if not pending_version or tuple(map(int, new.groups())) <= tuple(map(int, pending_version.groups())):
            raise ValueError("Refusing to replace or downgrade an existing update branch")
        request("/contents/Casks/mountfs.rb", token, {
            "message": f"Update Homebrew cask to {release['tag_name']}",
            "content": base64.b64encode(desired.encode()).decode(),
            "sha": pending["sha"], "branch": branch,
        })
    query = urlencode({"state": "open", "head": f"guoquan:{branch}", "base": "main"})
    prs = request(f"/pulls?{query}", token)
    if prs:
        pr = prs[0]
    else:
        try:
            pr = request("/pulls", token, {
                "title": f"Update Homebrew cask to {release['tag_name']}",
                "head": branch, "base": "main",
                "body": "Pin the latest published app archive and its GitHub SHA-256 digest. Merge after reviewing and validating the cask. This update preserves the main-branch pull-request requirement.",
            }, method="POST")
        except HTTPError:
            print(f"Update branch ready: https://github.com/{REPO}/compare/main...{branch}?expand=1", file=sys.stderr)
            print("Cask is not updated on main. Repository policy must allow Actions to create PRs, or open the update PR manually.", file=sys.stderr)
            raise
    print(f"Homebrew update PR ready: {pr['html_url']}; merge it to update the tap")



if __name__ == "__main__":
    main()
