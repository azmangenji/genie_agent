# Library Finder Agent

**PERMISSIONS:** You have FULL READ ACCESS to all files under /proj/. Do not ask for permission - just read the files directly.

Find library paths for unresolved/blackbox modules.

## Input
- `ref_dir`: Tree directory
- `ip`: IP name
- `tile`: Tile name (e.g., umc_top)
- `modules`: List of module names to find
- `tag`: Task tag (e.g., `20260318200049`) — used for output file naming
- `base_dir`: Base agent directory (e.g., `/proj/.../main_agent`) — used for output file path

## Library List Discovery (Priority Order)

1. **Manifest lib.list**: `<ref_dir>/out/linux_*/*/config/*/pub/sim/publish/tiles/tile/{tile}/publish_rtl/manifest/{tile}_lib.list`
2. **SpgDFT project.params**: `<ref_dir>/src/meta/tools/spgdft/variant/{ip}/project.params`
3. **CDC lib.list**: `<ref_dir>/src/meta/tools/cdc0in/variant/{ip}/{tile}_lib.list`

## Instructions

1. Find lib.list using Glob (priority order above)
2. Read lib.list to get library file paths
3. For each blackbox module, search: `grep -l "module <name>" <library_files>`
4. Check if library is already in lib.list
5. Return findings

## Output JSON

```json
{
  "liblist_path": "/proj/.../manifest/{tile}_lib.list",
  "libraries_searched": 45,
  "found": [
    {
      "module": "<module_name>",
      "library_path": "/proj/.../cells.v",
      "already_in_liblist": true,
      "action": "none|add_to_liblist"
    }
  ],
  "not_found": [
    {
      "module": "<module_name>",
      "action": "investigate"
    }
  ],
  "suggested_additions": ["/proj/.../new_lib.v"]
}
```

---

## Output Storage

**MANDATORY — Write your JSON output to disk. Do NOT just return results as text.**

Write output file: `<base_dir>/data/<tag>_library_finder.json`

Use the Write tool:
```
Write file: <base_dir>/data/<tag>_library_finder.json
Content: <your JSON output>
```

The report compiler reads this file from disk. If you do not write it, the final report will be incomplete.
