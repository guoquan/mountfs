import base64
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

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
        with patch.object(updater, "request", side_effect=[release(20), current, {"object": {"sha": "main-head"}}, {}, current, {}, [], {"html_url": "https://github.com/guoquan/mountfs/pull/1"}]) as request, \
             patch.dict(updater.os.environ, {"GH_TOKEN": "test"}), patch.object(updater.sys, "argv", ["updater"]):
            updater.main()
        payload = request.call_args_list[5].args[2]
        self.assertEqual(payload["sha"], "old-blob")
        self.assertEqual(payload["branch"], "homebrew/v0.3.4-build.20")
        self.assertEqual(request.call_args_list[3].kwargs["method"], "POST")
        self.assertEqual(request.call_args.kwargs["method"], "POST")
        self.assertIn('version "0.3.4,20"', base64.b64decode(payload["content"]).decode())

    def test_retry_reuses_existing_branch_and_pr_without_writing(self):
        old = {"content": base64.b64encode(updater.render(release()).encode()).decode(), "sha": "old"}
        desired = {"content": base64.b64encode(updater.render(release(20)).encode()).decode(), "sha": "new"}
        exists = HTTPError("refs", 422, "exists", None, None)
        replies = [release(20), old, {"object": {"sha": "head"}}, exists, {}, desired,
                   [{"html_url": "https://github.com/guoquan/mountfs/pull/1"}]]
        with patch.object(updater, "request", side_effect=replies) as request, \
             patch.dict(updater.os.environ, {"GH_TOKEN": "test"}), patch.object(updater.sys, "argv", ["updater"]):
            updater.main()
        self.assertEqual(request.call_count, 7)
        self.assertFalse(any(call.args[0] == "/contents/Casks/mountfs.rb" for call in request.call_args_list))

    def test_pr_policy_error_reports_branch_without_writing_main(self):
        old = {"content": base64.b64encode(updater.render(release()).encode()).decode(), "sha": "old"}
        replies = [release(20), old, {"object": {"sha": "head"}}, {}, old, {}, [],
                   HTTPError("pulls", 403, "policy", None, None)]
        with patch.object(updater, "request", side_effect=replies) as request, \
             patch.dict(updater.os.environ, {"GH_TOKEN": "test"}), patch.object(updater.sys, "argv", ["updater"]), \
             patch.object(updater.sys, "stderr") as stderr:
            with self.assertRaises(HTTPError):
                updater.main()
        self.assertIn("Update branch ready", str(stderr.write.call_args_list))
        self.assertTrue(all(call.args[2]["branch"] != "main" for call in request.call_args_list
                            if call.args[0] == "/contents/Casks/mountfs.rb"))

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
