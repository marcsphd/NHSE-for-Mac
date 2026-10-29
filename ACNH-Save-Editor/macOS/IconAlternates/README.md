# Saved alternate app icon

The active icon is **Inventory Tiles**, concept 6 (`../AppIcon.png` and `../AppIcon.icns`).

**Leaf & Pencil**, concept 1, is preserved here as `LeafAndPencil.png` and `LeafAndPencil.icns` for future testing. Original generated images remain in the project’s `Design/Icon Concepts/` folder.

To create a separate app build with the alternate, run from the `macOS` folder:

```sh
ACNH_APP_ICON="$PWD/IconAlternates/LeafAndPencil.icns" ACNH_BUILD_SCRATCH=/private/tmp/NHSE-Mac-Build ACNH_BUILD_OUTPUT=/private/tmp/NHSE-Mac-Alternate ./scripts/build-app.sh
```

This leaves the default icon unchanged. Quit the running editor before opening the alternate build. Both icons were generated with the built-in image generator; generation prompts are recorded in `../ICON-PROVENANCE.json`.
