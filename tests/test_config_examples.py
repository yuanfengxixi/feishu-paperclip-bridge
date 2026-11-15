from pathlib import Path
import unittest

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11
    import tomli as tomllib


ROOT = Path(__file__).resolve().parents[1]
CONFIGS = (
    ROOT / "wsl/cc-connect.config.toml.example",
    ROOT / "windows/cc-connect.config.toml.example",
)


class ConfigExampleTests(unittest.TestCase):
    def test_examples_are_valid_toml_and_keep_credentials_as_placeholders(self):
        for path in CONFIGS:
            with self.subTest(path=path.name):
                config = tomllib.loads(path.read_text(encoding="utf-8"))
                projects = config.get("projects")
                self.assertIsInstance(projects, list)
                self.assertGreater(len(projects), 0)

                for project in projects:
                    platforms = project.get("platforms", [])
                    self.assertTrue(platforms)
                    for platform in platforms:
                        options = platform.get("options", {})
                        for key in ("app_id", "app_secret"):
                            value = options.get(key, "")
                            self.assertTrue(
                                value.startswith("REPLACE_WITH_"),
                                f"{path.name}: {key} must remain a placeholder",
                            )

    def test_windows_example_has_three_independent_projects(self):
        config = tomllib.loads(CONFIGS[1].read_text(encoding="utf-8"))
        self.assertEqual(
            [project["name"] for project in config["projects"]],
            ["default", "knowledge-base", "design-orders"],
        )

    def test_wsl_example_has_one_project(self):
        config = tomllib.loads(CONFIGS[0].read_text(encoding="utf-8"))
        self.assertEqual(len(config["projects"]), 1)


if __name__ == "__main__":
    unittest.main()
