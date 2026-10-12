import base64
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("updater", ROOT / "scripts/update-homebrew.py")
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


def release(build=19):
    name = "mouNTFS-0.3.4-dev-arm64.zip"
    return {"tag_name": f"v0.3.4-build.{build}", "draft": False, "prerelease": False,
            "assets": [{"name": name, "state": "uploaded", "digest": "sha256:" + "a" * 64,
                        "browser_download_url": f"https://github.com/guoquan/mountfs/releases/download/v0.3.4-build.{build}/{name}"}]}


class CaskTests(unittest.TestCase):
    def test_untrusted_or_unfinished_assets_rejected(self):
        for key, value in [("browser_download_url", "https://example.com/app.zip"),
                           ("digest", "sha256:bad"), ("state", "new")]:
            data = release()
            data["assets"][0][key] = value
            with self.assertRaises(ValueError):
                updater.render(data)
        for key in ["draft", "prerelease"]:
            data = release()
            data[key] = True
            with self.assertRaises(ValueError):
                updater.render(data)

    def test_build_only_upgrade_and_concurrent_blob_check(self):
        old = updater.render(release())
        current = {"content": base64.b64encode(old.encode()).decode(), "sha": "old-blob"}
        with patch.object(updater, "request", side_effect=[release(20), current, {}]) as request, \
             patch.dict(updater.os.environ, {"GH_TOKEN": "test"}), patch.object(updater.sys, "argv", ["updater"]):
            updater.main()
        payload = request.call_args.args[2]
        self.assertEqual(payload["sha"], "old-blob")
        self.assertEqual(payload["branch"], "main")
        self.assertIn('version "0.3.4,20"', base64.b64decode(payload["content"]).decode())

    def test_downgrade_and_same_version_replacement_refused(self):
        old = updater.render(release(20))
        for incoming in [release(19), release(20)]:
            incoming["assets"][0]["digest"] = "sha256:" + "b" * 64
            with patch.object(updater, "request", side_effect=[incoming, {"content": base64.b64encode(old.encode()).decode(), "sha": "old"}]) as request, \
                 patch.dict(updater.os.environ, {"GH_TOKEN": "test"}), patch.object(updater.sys, "argv", ["updater"]):
                with self.assertRaises(ValueError):
                    updater.main()
                self.assertEqual(request.call_count, 2)

    def test_unchanged_release_does_not_commit(self):
        data = release()
        current = {"content": base64.b64encode(updater.render(data).encode()).decode(), "sha": "old"}
        with patch.object(updater, "request", side_effect=[data, current]) as request, \
             patch.dict(updater.os.environ, {"GH_TOKEN": "test"}), patch.object(updater.sys, "argv", ["updater"]):
            updater.main()
        self.assertEqual(request.call_count, 2)


if __name__ == "__main__":
    unittest.main()
