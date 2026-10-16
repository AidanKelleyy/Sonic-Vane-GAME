import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("startup_dependencies", Path(__file__).parents[1] / "validate_startup_dependencies.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StartupDependencyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("LS5Framework/Scripts/Player/Player.gd", 'extends PlayerBase\nvar config = preload("res://LS5Framework/Resources/Config.tres")\n# preload("res://missing_comment.tres")\nvar example = "FakeClass"\n')
        self.write("LS5Framework/Scripts/PlayerBase.gd", "class_name PlayerBase\nextends Node\nvar helper: SupportClass\n")
        self.write("LS5Framework/Scripts/Support.gd", "class_name SupportClass\nextends Node\nvar loop: PlayerBase\n")
        self.write("LS5Framework/Resources/Config.tres", '[gd_resource type="Resource" format=3]\n[ext_resource type="Texture2D" path="res://LS5Framework/Images/test.png" id="1"]\n')
        self.write("LS5Framework/Images/test.png", "fixture")
        self.write(module.VALIDATOR[6:], "extends RefCounted\n")
        self.write(module.VERIFY[6:], "extends SceneTree\n")
        sections = []
        for index, name in enumerate(sorted(module.PLATFORMS)):
            sections.append(f'[preset.{index}]\nname="{name}"\nexport_filter="resources"\nexport_files=PackedStringArray()\ninclude_filter=""\nexclude_filter=""\n')
        self.cfg = self.root / "export_presets.cfg"
        self.cfg.write_text("\n".join(sections), encoding="utf-8")

    def write(self, path, source):
        path = self.root / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8")

    def test_transitive_classes_preloads_and_resource_dependencies(self):
        module.validate(self.root, self.cfg, fix=True)
        manifest = json.loads((self.root / module.MANIFEST[6:]).read_text())
        paths = {entry["path"] for entry in manifest["required_resources"]}
        self.assertIn("res://LS5Framework/Scripts/Support.gd", paths)
        self.assertIn("res://LS5Framework/Images/test.png", paths)
        self.assertNotIn("res://missing_comment.tres", paths)
        for preset in module.read_presets(self.cfg.read_text()):
            self.assertTrue(paths.issubset(set(preset["files"])))
            self.assertIn(module.MANIFEST, preset["includes"])
        module.validate(self.root, self.cfg)

    def test_synchronization_is_idempotent(self):
        module.validate(self.root, self.cfg, fix=True)
        before = self.cfg.read_bytes(), (self.root / module.MANIFEST[6:]).read_bytes()
        module.validate(self.root, self.cfg, fix=True)
        after = self.cfg.read_bytes(), (self.root / module.MANIFEST[6:]).read_bytes()
        self.assertEqual(before, after)

    def test_new_preload_requires_regeneration_and_export_selection(self):
        module.validate(self.root, self.cfg, fix=True)
        self.write("LS5Framework/new.tres", "[gd_resource format=3]\n")
        with (self.root / "LS5Framework/Scripts/Player/Player.gd").open("a") as file:
            file.write('var extra = preload("res://LS5Framework/new.tres")\n')
        with self.assertRaisesRegex(ValueError, "missing startup dependency"):
            module.validate(self.root, self.cfg)
        module.validate(self.root, self.cfg, fix=True)
        module.validate(self.root, self.cfg)

    def test_missing_source_is_fatal_and_does_not_modify_presets(self):
        (self.root / "LS5Framework/Images/test.png").unlink()
        before = self.cfg.read_bytes()
        with self.assertRaisesRegex(ValueError, "Missing startup dependency"):
            module.validate(self.root, self.cfg, fix=True)
        self.assertEqual(before, self.cfg.read_bytes())

    def test_exclusion_filter_cannot_remove_required_asset(self):
        self.cfg.write_text(self.cfg.read_text().replace('exclude_filter=""', 'exclude_filter="*.gd"'))
        with self.assertRaisesRegex(ValueError, "excludes startup dependency"):
            module.validate(self.root, self.cfg, fix=True)

    def test_script_only_change_invalidates_manifest(self):
        module.validate(self.root, self.cfg, fix=True)
        with (self.root / module.VALIDATOR[6:]).open("a") as file:
            file.write("var changed: bool = true\n")
        with self.assertRaisesRegex(ValueError, "manifest is stale"):
            module.validate(self.root, self.cfg)

    def test_relative_inheritance_is_followed(self):
        self.write("LS5Framework/Scripts/Player/Player.gd", 'extends "../PlayerBase.gd"\n')
        module.validate(self.root, self.cfg, fix=True)
        manifest = json.loads((self.root / module.MANIFEST[6:]).read_text())
        self.assertIn("res://LS5Framework/Scripts/Support.gd", {entry["path"] for entry in manifest["required_resources"]})

    def test_autoload_class_dependencies_are_bootstrap_roots(self):
        self.write("project.godot", '[autoload]\nBoot="*res://LS5Framework/Boot.gd"\n')
        self.write("LS5Framework/Boot.gd", "extends Node\nvar support: SupportClass\n")
        module.validate(self.root, self.cfg, fix=True)
        manifest = json.loads((self.root / module.MANIFEST[6:]).read_text())
        self.assertIn("res://LS5Framework/Boot.gd", {entry["path"] for entry in manifest["required_resources"]})

    def test_escaped_apostrophe_in_godot_path(self):
        self.assertEqual(module.tokens(r'"res://Sound/Cannon\'s.wav"'), [("string", "res://Sound/Cannon's.wav")])


if __name__ == "__main__":
    unittest.main()
