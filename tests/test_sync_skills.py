import json
import os
import stat
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "cli"))
import sync_skills  # noqa: E402


def make_skill(path, name=None):
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True)
    skill_name = name or path.name
    (path / "SKILL.md").write_text(
        f"---\nname: {skill_name}\ndescription: test\n---\nbody\n"
    )
    return path


def make_exe(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/sh\nexit 0\n")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


class SyncSkillsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.builtin = self.root / "builtin-skills"
        make_skill(self.builtin / "agency-desktop")
        make_skill(self.builtin / "agency-system")
        self.instructions = self.root / "agency-instructions.md"
        self.instructions.write_text("# This machine\n")

    def tearDown(self):
        self.tmp.cleanup()

    def base_config(self, chosen=()):
        chosen = set(chosen)
        return {
            "hub": ".agents/skills",
            "providers": [
                {
                    "id": "claude-code",
                    "program": "claude",
                    "chosen": "claude-code" in chosen,
                    "skills": ".claude/skills",
                    "instructions": ".claude/CLAUDE.md",
                },
                {
                    "id": "codex",
                    "program": "codex",
                    "chosen": "codex" in chosen,
                    "skills": ".codex/skills",
                    "instructions": ".codex/AGENTS.md",
                },
                {
                    "id": "opencode",
                    "program": "opencode",
                    "chosen": "opencode" in chosen,
                    "skills": ".config/opencode/skills",
                    "instructions": ".config/opencode/AGENTS.md",
                },
                {
                    "id": "antigravity",
                    "program": "agy",
                    "chosen": "antigravity" in chosen,
                    "skills": ".gemini/config/skills",
                    "instructions": ".gemini/GEMINI.md",
                },
                {
                    "id": "copilot-cli",
                    "program": "copilot",
                    "chosen": "copilot-cli" in chosen,
                    "skills": ".copilot/skills",
                    "instructions": ".copilot/copilot-instructions.md",
                },
                {
                    "id": "devin",
                    "program": "devin",
                    "chosen": "devin" in chosen,
                    "skills": ".config/devin/skills",
                    "instructions": ".config/devin/AGENTS.md",
                },
            ],
        }

    def run_sync(self, config, wait=False):
        sync_skills.sync(
            home=self.home,
            config=config,
            builtin_skills=self.builtin,
            instructions=self.instructions,
            wait=wait,
            extra_path="",
        )

    def test_only_installed_providers_are_linked(self):
        # claude-code via settings.apps, antigravity via ~/.local/bin/agy,
        # copilot-cli via ~/.bun/bin/copilot. codex/opencode/devin uninstalled.
        make_exe(self.home / ".local/bin/agy")
        make_exe(self.home / ".bun/bin/copilot")
        self.run_sync(self.base_config(chosen=["claude-code"]))

        hub = self.home / ".agents/skills"
        for name in ("agency-desktop", "agency-system"):
            self.assertTrue((hub / name).is_symlink())
            self.assertEqual(os.readlink(hub / name), str(self.builtin / name))

        for rel in (".claude/skills", ".gemini/config/skills", ".copilot/skills"):
            for name in ("agency-desktop", "agency-system"):
                link = self.home / rel / name
                self.assertTrue(link.is_symlink(), f"missing {link}")
                self.assertEqual(os.readlink(link), str(hub / name))

        # Instructions linked for installed providers only.
        self.assertEqual(os.readlink(self.home / ".claude/CLAUDE.md"), str(self.instructions))
        self.assertEqual(os.readlink(self.home / ".gemini/GEMINI.md"), str(self.instructions))
        self.assertEqual(
            os.readlink(self.home / ".copilot/copilot-instructions.md"),
            str(self.instructions),
        )

        # Uninstalled providers are untouched (no clutter dirs created).
        self.assertFalse((self.home / ".codex").exists())
        self.assertFalse((self.home / ".config/opencode").exists())
        self.assertFalse((self.home / ".config/devin").exists())

        # Claude default setting written because claude-code is installed.
        settings = json.loads((self.home / ".claude/settings.json").read_text())
        self.assertIs(settings["remoteControlAtStartup"], True)

    def test_claude_settings_not_created_when_uninstalled(self):
        self.run_sync(self.base_config(chosen=["codex"]))
        self.assertFalse((self.home / ".claude").exists())

    def test_claude_settings_respects_existing_value_and_bad_json(self):
        settings_path = self.home / ".claude/settings.json"
        settings_path.parent.mkdir(parents=True)
        settings_path.write_text(json.dumps({"remoteControlAtStartup": False}))
        self.run_sync(self.base_config(chosen=["claude-code"]))
        self.assertIs(json.loads(settings_path.read_text())["remoteControlAtStartup"], False)

        settings_path.write_text("{not json")
        self.run_sync(self.base_config(chosen=["claude-code"]))
        self.assertEqual(settings_path.read_text(), "{not json")

    def test_hub_user_skill_distributed_to_all_installed_providers(self):
        make_skill(self.home / ".agents/skills/my-tool")
        self.run_sync(self.base_config(chosen=["claude-code", "codex", "antigravity", "devin"]))

        for rel in (
            ".claude/skills/my-tool",
            ".codex/skills/my-tool",
            ".gemini/config/skills/my-tool",
            ".config/devin/skills/my-tool",
        ):
            dest = self.home / rel
            self.assertTrue(dest.is_symlink())
            self.assertEqual(os.readlink(dest), str(self.home / ".agents/skills/my-tool"))

    def test_provider_skill_consolidated_into_hub_and_linked_everywhere(self):
        make_skill(self.home / ".claude/skills/custom-skill")
        # Provider-private folders must stay untouched in ~/.claude/skills.
        (self.home / ".claude/skills/synced/bucket/nested").mkdir(parents=True)
        (self.home / ".claude/skills/.trash/old").mkdir(parents=True)

        self.run_sync(self.base_config(chosen=["claude-code", "codex", "antigravity"]))

        hub_skill = self.home / ".agents/skills/custom-skill"
        self.assertTrue(hub_skill.is_dir() and not hub_skill.is_symlink())
        self.assertTrue((hub_skill / "SKILL.md").is_file())

        for rel in (
            ".claude/skills/custom-skill",
            ".codex/skills/custom-skill",
            ".gemini/config/skills/custom-skill",
        ):
            dest = self.home / rel
            self.assertTrue(dest.is_symlink())
            self.assertEqual(os.readlink(dest), str(hub_skill))

        # Private folders stayed in ~/.claude/skills and did NOT leak to hub or others.
        self.assertTrue((self.home / ".claude/skills/synced").is_dir())
        self.assertFalse((self.home / ".claude/skills/synced").is_symlink())
        self.assertTrue((self.home / ".claude/skills/.trash").is_dir())
        self.assertFalse((self.home / ".agents/skills/synced").exists())
        self.assertFalse((self.home / ".codex/skills/synced").exists())
        self.assertFalse((self.home / ".codex/skills/.trash").exists())

    def test_migrates_existing_reverse_symlinks(self):
        # Simulate an existing agency machine where real skills lived in
        # ~/.claude/skills and ~/.agents/skills + ~/.codex/skills symlinked there.
        real = make_skill(self.home / ".claude/skills/3d-printing")
        (self.home / ".agents/skills").mkdir(parents=True)
        (self.home / ".codex/skills").mkdir(parents=True)
        os.symlink(str(real), self.home / ".agents/skills/3d-printing")
        os.symlink(str(real), self.home / ".codex/skills/3d-printing")

        self.run_sync(self.base_config(chosen=["claude-code", "codex", "antigravity"]))

        hub_skill = self.home / ".agents/skills/3d-printing"
        self.assertTrue(hub_skill.is_dir() and not hub_skill.is_symlink())
        self.assertTrue((hub_skill / "SKILL.md").is_file())
        for rel in (
            ".claude/skills/3d-printing",
            ".codex/skills/3d-printing",
            ".gemini/config/skills/3d-printing",
        ):
            self.assertEqual(os.readlink(self.home / rel), str(hub_skill))

    def test_conflict_preserves_both_real_directories(self):
        hub_skill = make_skill(self.home / ".agents/skills/dup")
        (hub_skill / "marker").write_text("hub")
        claude_skill = make_skill(self.home / ".claude/skills/dup")
        (claude_skill / "marker").write_text("claude")

        self.run_sync(self.base_config(chosen=["claude-code", "codex"]))

        self.assertEqual((hub_skill / "marker").read_text(), "hub")
        self.assertEqual((claude_skill / "marker").read_text(), "claude")
        self.assertFalse(claude_skill.is_symlink())
        self.assertEqual(os.readlink(self.home / ".codex/skills/dup"), str(hub_skill))

    def test_external_symlink_shared_without_moving_source(self):
        external = make_skill(self.root / "repo/skills/ext-skill")
        (self.home / ".claude/skills").mkdir(parents=True)
        os.symlink(str(external), self.home / ".claude/skills/ext-skill")

        self.run_sync(self.base_config(chosen=["claude-code", "codex"]))

        # Source untouched, claude symlink untouched, hub + codex linked.
        self.assertTrue(external.is_dir() and not external.is_symlink())
        self.assertEqual(os.readlink(self.home / ".claude/skills/ext-skill"), str(external))
        self.assertEqual(os.readlink(self.home / ".agents/skills/ext-skill"), str(external.resolve()))
        self.assertEqual(
            os.readlink(self.home / ".codex/skills/ext-skill"),
            str(self.home / ".agents/skills/ext-skill"),
        )

    def test_deleting_skill_from_hub_prunes_dangling_provider_links(self):
        make_skill(self.home / ".agents/skills/temp-skill")
        cfg = self.base_config(chosen=["claude-code", "codex"])
        self.run_sync(cfg)
        self.assertTrue((self.home / ".claude/skills/temp-skill").is_symlink())

        # Also add an unrelated broken user symlink that must NOT be pruned.
        os.symlink("/nonexistent/user-path", self.home / ".claude/skills/user-broken")

        # Delete skill from hub and re-sync.
        for child in (self.home / ".agents/skills/temp-skill").iterdir():
            child.unlink()
        (self.home / ".agents/skills/temp-skill").rmdir()
        self.run_sync(cfg)

        self.assertFalse((self.home / ".claude/skills/temp-skill").is_symlink())
        self.assertFalse((self.home / ".codex/skills/temp-skill").is_symlink())
        self.assertTrue((self.home / ".claude/skills/user-broken").is_symlink())

    def test_replaces_old_nix_store_links_and_preserves_user_instructions(self):
        (self.home / ".claude/skills").mkdir(parents=True)
        os.symlink("/nix/store/oldhash-skills/agency-desktop", self.home / ".claude/skills/agency-desktop")
        os.symlink("/nix/store/oldhash-skills/retired-skill", self.home / ".claude/skills/retired-skill")
        (self.home / ".claude/CLAUDE.md").write_text("# my own instructions\n")
        (self.home / ".codex").mkdir(parents=True)
        os.symlink("/nix/store/oldhash-agency-instructions.md", self.home / ".codex/AGENTS.md")

        self.run_sync(self.base_config(chosen=["claude-code", "codex"]))

        self.assertEqual(
            os.readlink(self.home / ".claude/skills/agency-desktop"),
            str(self.home / ".agents/skills/agency-desktop"),
        )
        self.assertFalse((self.home / ".claude/skills/retired-skill").is_symlink())
        self.assertFalse((self.home / ".claude/CLAUDE.md").is_symlink())
        self.assertEqual((self.home / ".claude/CLAUDE.md").read_text(), "# my own instructions\n")
        self.assertEqual(os.readlink(self.home / ".codex/AGENTS.md"), str(self.instructions))

    def test_whole_dir_symlink_to_hub_is_respected(self):
        (self.home / ".agents/skills").mkdir(parents=True)
        (self.home / ".codex").mkdir(parents=True)
        os.symlink(str(self.home / ".agents/skills"), self.home / ".codex/skills")
        make_skill(self.home / ".agents/skills/shared")

        self.run_sync(self.base_config(chosen=["codex", "claude-code"]))

        self.assertEqual(os.readlink(self.home / ".codex/skills"), str(self.home / ".agents/skills"))
        self.assertEqual(
            os.readlink(self.home / ".claude/skills/shared"),
            str(self.home / ".agents/skills/shared"),
        )

    def test_wait_catches_fresh_dir_before_skill_md_written(self):
        fresh = self.home / ".claude/skills/delayed"
        fresh.mkdir(parents=True)

        def write_later():
            time.sleep(0.15)
            (fresh / "SKILL.md").write_text("---\nname: delayed\ndescription: x\n---\n")

        t = threading.Thread(target=write_later)
        t.start()
        try:
            self.run_sync(self.base_config(chosen=["claude-code", "codex"]), wait=True)
        finally:
            t.join()

        self.assertTrue((self.home / ".agents/skills/delayed/SKILL.md").is_file())
        self.assertEqual(
            os.readlink(self.home / ".codex/skills/delayed"),
            str(self.home / ".agents/skills/delayed"),
        )

    def test_idempotent_second_run_does_not_rewrite_links(self):
        make_skill(self.home / ".agents/skills/steady")
        cfg = self.base_config(chosen=["claude-code", "codex"])
        self.run_sync(cfg)
        link = self.home / ".claude/skills/steady"
        before_ino = link.lstat().st_ino
        self.run_sync(cfg)
        self.assertEqual(link.lstat().st_ino, before_ino)


if __name__ == "__main__":
    unittest.main()
