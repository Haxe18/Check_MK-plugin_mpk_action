# Checkmk Plugin Release Action

A reusable GitHub Workflow for building and releasing Checkmk plugins (MKP packages).

## Usage

Create a workflow file in your plugin repository (e.g., `.github/workflows/release.yml`):

```yaml
name: Release Plugin

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  release:
    uses: haxe18/Check_MK-plugin_mpk_action/.github/workflows/reusable_release.yml@main
    with:
      plugin_name: "my_plugin"
      title: "My Plugin Title"
      description: "Description of my plugin"
      tag_prefix: "v"
    secrets: inherit
```

## Plugin directory layout

`build_plugin.sh` packs `<plugin_name>/` into the MKP part `cmk_addons_plugins`
(`~/local/lib/python3/cmk_addons/plugins/`). Two subdirectories get their own part,
because Checkmk 2.4 does not load them from `cmk_addons`:

| Directory | MKP part | Installed to |
|-----------|----------|--------------|
| `<plugin_name>/bakery/` | `lib` | `~/local/lib/python3/cmk/base/cee/plugins/bakery/` |
| `<plugin_name>/agents/` | `agents` | `~/local/share/check_mk/agents/` (e.g. `agents/plugins/x` -> `plugins/x`) |

Notes:
- `--strip-comments` (and `--ci`) strips whole-line comments from `*.py` files in
  `cmk_addons_plugins` and `bakery/`, but not from files in `agents/`: agent plugins
  are shipped unchanged.
- `__pycache__` directories are never packed.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `plugin_name` | Name of the plugin directory | Yes | |
| `title` | Title of the plugin | Yes | |
| `description` | Description of the plugin | Yes | |
| `tag_prefix` | Tag prefix to strip (e.g., 'v') | No | "v" |
| `changelog_filter_path` | Path to filter git log | No | "." |
