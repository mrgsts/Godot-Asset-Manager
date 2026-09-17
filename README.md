<div align="center">
<a href="https://github.com/kivylius/asset-manager/" rel="noopener" target="_blank"><img src="https://img.shields.io/badge/NOTICE:-This_project_is_in_early_development!-orange.svg" alt="This_project_is_in_early_development"></a>
<p> </p>
</div>

<!-- markdownlint-disable-next-line -->
<p align="center">
  <a href="https://github.com/kivylius/asset-manager/" rel="noopener" target="_blank"><img src="cover.png" alt="asset maanger cover" style="border-radius:8px"></a>
</p>

<h1 align="center">Asset-Manager (Godot)</h1>

<div align="center">

[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](https://github.com/kivylius/asset-manager/blob/main/LICENSE)
[![Versions](https://img.shields.io/badge/versions-v1.0.6-green.svg)](https://github.com/kivylius/asset-manager/releases)
[![Platform](https://img.shields.io/badge/godot-4.x-red.svg)](https://github.com/kivylius/asset-manager)
[![Language](https://img.shields.io/badge/Language-GDscript-pink.svg)](https://github.com/kivylius/asset-manager)
[![Made with Godot](https://img.shields.io/badge/Made%20with-Godot-478CBF?style=flat&logo=godot%20engine&logoColor=white)](https://godotengine.org)

</div>

Manage all your Godot assets in a single place, get previews and send files directly into project(s). Supports Godot 4.x on Mac/Linux & Windows.

## Key Features

- Shared asset library outside any project
- Live preview for models, materials, shaders, effects/vfx, hdri's, audio, video, images & themes
- Drag-and-drop any asset pack or file straight in
- Search & filtering across your whole assets directory
- Multi-workspace support & shared assets for collaboration
- Tagging assets with custom names
- Thumbnail generation for all asset types
- Export destination per project/game
- Grid & list toggable views
- Right-click to send project assets to the library
- **Unreal2Godot packs**: keep Unreal exports as they are in the library, browse
  their prefabs, meshes, materials and levels with previews, and send any of them
  into a project with everything it needs ([details](#unreal2godot-packs))

## Unreal2Godot packs

Exports made with Unreal2Godot are kept in the library exactly as the exporter
writes them, in the `unreal/` folder of the workspace:

```
<workspace>/unreal/<Pack>/            (optionally unreal/<Vendor>/<Pack>/)
    project.godot
    Prefabs/  Shaders/  Engine/  L_Overview.tscn  WorldEnvironment.tscn
    <Pack>/Meshes/  <Pack>/Materials/  <Pack>/Textures/
```

- Add one with **Add → unreal**, or drop the export folder (or a folder holding
  several exports) onto the Asset Manager tab. The `.godot` cache is left out;
  the `.import` files are kept.
- Prefabs, meshes, materials and levels are listed, filterable by kind, and
  recognised by what they are rather than where they sit, whatever content
  tree the Unreal project used (`Meshes/Props`, `Mesh/CaveModules`,
  `Assets/Candle/Static_Mesh`...).
- Tags come from the vendor and pack folder names, plus, for meshes and the
  prefabs built on them, the folder holding the model (`props`, `candle`),
  skipping generic ones like `Meshes` or `Static_Mesh`. Rebuild keeps these up
  to date without touching tags added or removed by hand.
- **Send to Project** copies the asset and everything it uses to
  `res://assets/unreal/<Pack>/`, keeping the export's layout below it. Packs stay
  apart because every export has its own `Prefabs/`, `Shaders/` and `Engine/`,
  often with different files under the same names. References are repointed,
  uids renewed (the exporter repeats them across packs) and import settings kept.
- Large textures are shrunk once for previews and thumbnails, in the per-machine
  cache folder (`AssetManager/preview_textures`).

## Requirements:

- Godot version: 4.4 minimum, 4.7+ recommended (built and tested on 4.7)
- Platform: Windows, macOS, Linux (no native code, should work anywhere)

## Installation

You can clone this repo and add `/addons/**` to your project or use the Godot Asset Store:

[![Godot Engine](https://img.shields.io/badge/Godot-Asset_Store_⧉-%23FFFFFF.svg?logo=godot-engine)](https://store.godotengine.org/asset/kivylius/asset-manager/)

## Development

All source code is available and no extra libraries are required to start.

## Credits

Forked from [Global-Asset-Manager](https://github.com/sn1ks0h/Global-Asset-Manager)

---

Copyright (C) 2026 Kivylius

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
