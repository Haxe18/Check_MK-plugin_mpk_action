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

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `plugin_name` | Name of the plugin directory | Yes | |
| `title` | Title of the plugin | Yes | |
| `description` | Description of the plugin | Yes | |
| `tag_prefix` | Tag prefix to strip (e.g., 'v') | No | "v" |
| `changelog_filter_path` | Path to filter git log | No | "." |
