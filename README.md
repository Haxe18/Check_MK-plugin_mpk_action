# Checkmk Plugin Release Action

A GitHub Action for building and releasing Checkmk plugins (MKP packages).
It builds the MKP, writes a changelog from the git log and creates a GitHub release.

## Usage

Create a workflow file in your plugin repository (e.g., `.github/workflows/release.yml`):

```yaml
name: Release Plugin

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0  # all tags and commits, needed for the changelog

      - uses: haxe18/Check_MK-plugin_mpk_action@v1
        with:
          plugin_name: "my_plugin"
          title: "My Plugin Title"
          description: "Description of my plugin"
          tag_prefix: "v"
```

Pin a version tag (`@v1`, `@v1.2.0`) so a change on `main` does not affect your releases.
The build script always comes from the same version as the action.

### Old setup: reusable workflow

`.github/workflows/reusable_release.yml` still works for existing plugin repos and takes
the same inputs. It always runs the action from `main`, so version pinning does not
apply there:

```yaml
permissions:
  contents: write

jobs:
  release:
    uses: haxe18/Check_MK-plugin_mpk_action/.github/workflows/reusable_release.yml@main
    with:
      plugin_name: "my_plugin"
      title: "My Plugin Title"
      description: "Description of my plugin"
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
| `github_token` | Token used to create the release (action only) | No | `github.token` |

## Outputs

| Output | Description |
|--------|-------------|
| `mkp_file` | File name of the built MKP package (action only) |
