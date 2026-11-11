import pathlib
import tempfile
import unittest

import hermetic_tools as ht


class Lexer(unittest.TestCase):
    def test_a_quoted_parenthesis_inside_a_command_substitution_ends_nothing(self):
        found = ht.commands("""out="$(printf '%s)' "$x" | sed 's/a/b/')"\n""")
        self.assertIn("printf", found)
        self.assertIn("sed", found)
        self.assertNotIn("a", found)

    def test_a_one_line_function_after_a_semicolon_is_a_function(self):
        names = ht.function_names_text("set -e; files() { ls; }\nif true; then a() { :; }; fi\n")
        self.assertEqual({"files", "a"}, names & {"files", "a"})

    def test_shfmt_comes_from_the_sh_tool(self):
        self.assertIn("shfmt", ht.BINARIES.get("sh", []))


if __name__ == "__main__":
    unittest.main()


class Declared(unittest.TestCase):
    def test_the_tools_of_the_shared_conf_d_file_count_as_pinned(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            (root / ".config/mise/conf.d").mkdir(parents=True)
            (root / "mise.toml").write_text('[tools]\nyq = "4.54.3"\n')
            (root / ".config/mise/conf.d/shared-tools.toml").write_text('[tools]\nshellcheck = "0.11.0"\n"pipx:yamllint" = "1.38.0"\n')
            names = ht.declared(root / "mise.toml")
        self.assertTrue({"yq", "shellcheck", "yamllint"} <= names)
