# Vendored Blender helpers

Copied on 2026-11-03 UTC from the locally installed `blender-image-to-3d` skill:
`/Users/hayatok/.codex/skills/blender-image-to-3d/scripts/`.

Only `init_master.py`, `export_delivery.py` and `validate.py` are required by this
pipeline. The copied modules import only Python standard-library modules and
Blender's bundled `bpy`, `bmesh`, `mathutils`; they do not import other skill files.
The scripts are preserved without behavior changes. Their original docstrings,
including generic usage examples, are retained.

License evidence: the source package's `SKILL.md` YAML frontmatter declares
`license: MIT`. No separate LICENSE file or copyright notice was supplied in that
local package. No upstream author, remote URL or revision was supplied; these
have not been invented. The local source paths and date identify the snapshot.
The standard MIT permission text is included in `LICENSE-MIT.txt` with that
qualification. This is provenance, not a quality or acceptance check.
