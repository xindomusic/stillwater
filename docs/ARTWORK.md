# Artwork

Stillwater’s bundled scenes and fish views were generated specifically for this project with OpenAI’s image generation tool. They are included locally and require no AI service at runtime. They are photographic-style generated images, not footage of live animals.

| Asset | Use |
| --- | --- |
| `Resources/Scenes/riverlight-crystal.png` | Clear river stones, sand, and planted edges |
| `Resources/Scenes/sunken-grove-crystal.png` | Sculptural wood and planted grove |
| `Resources/Scenes/willow-springs-crystal.png` | Willow roots and clear spring water |
| `Resources/Fish/rasbora-turns.png` | Eight harlequin rasbora views |
| `Resources/Fish/cherry-turns.png` | Eight cherry barb views |
| `Resources/Fish/pearl-turns.png` | Eight pearl gourami views |
| `Resources/Fish/loach-turns.png` | Eight kuhli loach views |
| `Resources/AppIcon.icns` | App icon drawn by `tools/create-icon.swift` |

[Scene prompts](../Resources/ASSET_PROMPTS.md) and [fish prompts](../Resources/Fish/TURNTABLE_PROMPTS.md) are retained for provenance. The continuous turn renderer uses a photographic profile from each atlas as its body and fin material. Pose rectangles are defined in `Sources/Artwork.swift`; generated atlas columns are not uniformly spaced.

Documentation images come from the app’s own renderer and settings. They do not include a user’s desktop or other applications. The settings captures replace the Metal preview with a renderer snapshot, while preserving production controls and layout.

The source, documentation, and bundled project artwork are distributed under the [MIT license](../LICENSE).
