# ACNH Save Editor for Mac

An independent native SwiftUI macOS adaptation primarily based on [NHSE](https://github.com/kwsch/NHSE), using its save-format research and editor behavior. [cbreezy210/ACNH-Save-Editor](https://github.com/cbreezy210/ACNH-Save-Editor) provided the initial foundation and selected save-cryptography routines. Requires macOS 14 or later. The universal build supports Apple silicon and Intel Macs. Works offline without third-party runtimes.

## Open the app

Extract the app release ZIP into a local folder such as Downloads, then drag `ACNH Save Editor.app` to Applications and open it there. Keep the ZIP as the portable copy, especially when storing releases in a cloud-synced project folder. The local build is ad-hoc signed; it is not Developer ID signed or notarized for public distribution.

## App icon

The default icon is **Inventory Tiles** (concept 6). Its editable source image is `AppIcon.png`, and the app bundles `AppIcon.icns`. **Leaf & Pencil** (concept 1) is preserved as both PNG and ICNS in `IconAlternates/` for later testing.

Recreate the default icon with `./scripts/make-app-icon.sh AppIcon.png AppIcon.icns`. To build with the alternate without replacing the default:

```sh
ACNH_APP_ICON="$PWD/IconAlternates/LeafAndPencil.icns" ACNH_BUILD_SCRATCH=/private/tmp/NHSE-Mac-Build ACNH_BUILD_OUTPUT=/private/tmp/NHSE-Mac-Alternate ./scripts/build-app.sh
```

## Use an exported save

1. Fully close Animal Crossing on your Switch. Export a complete save with your save manager and copy that folder to your Mac.
2. Open the folder containing `main.dat`, `mainHeader.dat`, and `Villager0/personal.dat` plus `Villager0/personalHeader.dat`.
3. Use **Player Settings** for the primary resident's name and birthday, **Island Settings** for island name, hemisphere, airport color, weather, fruit, and flowers, and **Storage** for their unlocked home storage. You can also edit terrain, paths, outdoor items, buildings, animal villagers, wallet Bells, bank Bells, Nook Miles, house loan, or all the primary resident's unlocked pockets (up to 40).
4. Choose **Review Changes**, then **Export Copy** to create a complete edited save folder. Import that folder on your Switch with the game closed.
5. Alternatively, **Save to Original** updates the opened folder after backing up and verifying the complete source folder. The Backups screen can open, reveal, and restore snapshots. Restoring creates another backup first.

Supported save revisions: **ACNH 3.0.0–3.0.3**. Versions, file sizes, paired encryption headers, all supported main/resident file Murmur3 regions, and edited money fields are checked. Unsupported or damaged saves are rejected. The app does not repair previously corrupted saves or write directly to a connected Switch.

Save edits always carry risk. Keep a separate original backup and use offline. This port has been tested with generated fixtures and an isolated copy of an ACNH 3.0.3 island. Importing an edited save back into the game remains untested. Not affiliated with Nintendo.

## Mac features

- Native SwiftUI window, sidebar, menus, file dialogs, folder drag and drop, dark mode, and keyboard shortcuts.
- Draft edits, undo/redo (one step per brush stroke), revert, and a review sheet before in-place saves.
- Player Settings: primary resident name and birthday (including the profile birthday). Names support up to 10 UTF-16 units; emoji may use multiple units. Birthdays use valid calendar dates, including February 29.
- Island Settings: island name, northern/southern hemisphere, airport color, island/tour weather seeds and hemispheres, native/sister fruits and flowers. Changing native fruit also updates the island fruit flags and primary resident's profile fruit; existing planted objects are preserved.
- Player/island renames propagate matching 24-byte ID-and-name identities through main.dat and supported files in Villager0–Villager7, following NHSE's identity replacement behavior. This includes personal, postbox, photo_studio_island, profile, and optional wherearen files. Only files present are required, but incomplete, corrupted, or mismatched pairs are rejected. Encryption headers, numeric IDs, unrelated names, and opaque sibling files are preserved.
- A zoomable island map: select tiles, paint terrain and paths with 1×1 / 3×3 / 5×5 brushes, set terrain models / elevation / rotation, and inspect both outdoor item layers.
- Drop catalog items with correct 2×2 footprints; remove existing objects with their linked extension cells.
- Move existing buildings with terrain-aligned markers and half-tile coordinate steps, preserving their identity and interior.
- Edit all 10 animal-villager slots: searchable selection from 417 identities with portraits, personality, catchphrase, moving-out state, and friendship for existing player memories. Empty slots are shown but cannot be populated.
- Item search, 22 curated favorites, item-specific stack limits and zero-based save quantities.
- NHSE inventory icons in the pocket grid, item library, and selected-item previews. Icons are bundled for offline use; furniture and other items use the same shared menu icons as NHSE. Optional external per-item image packs are not included.
- All unlocked pocket slots are read from both saved pocket blocks in game order, including 20-, 30-, and 40-slot inventories. Locked records and capacity counters are preserved; this screen does not unlock pocket upgrades.
- A Storage tab for the primary resident's unlocked home storage (up to 9,000 slots in the supported save format), with offline item icons, fifty-slot pages, first/last navigation, search by stored name or hex ID, an occupied-only filter, and Find Empty Slot. Add/replace/remove items through the shared item library; update stack quantities while preserving the item's other saved bytes. Storage edits join draft undo/redo, review, export/save, backups, restore, and Revert Storage Changes. Locked records and storage capacity are preserved. Inventory-file import/export is not included.
- Select multiple pocket or storage slots and place the same library item in all of them at once. Shift-click selects a range; ⌘-click adds or removes individual slots. A plain click selects one slot. A brief hint and count explain the shortcuts. Storage selection is limited to the visible page and filtered results. The placement panel shows occupied destinations and quantity per slot. Each batch placement or clear is one undo step.
- Five persistent pocket loadouts. Existing 20-slot loadouts remain compatible; new loadouts save the current capacity. Applying a smaller loadout preserves remaining pockets, while a larger loadout requires enough unlocked space. Applying a loadout changes the draft until you export or save.
- Timestamped full-folder backups with SHA-256 verification, external-change detection, atomic per-file writes, and rollback on write errors.
- Interrupted writes leave a marker: the app refuses that folder until you recover by opening a verified backup and exporting a separate copy. A multi-file update cannot be atomic across a power failure.
- Clearly labeled preview mode; preview values cannot be exported or written as a save.

Backups and loadouts are stored in `~/Library/Application Support/ACNH Save Editor/`.

Shortcuts: **⌘O** open, **⌘S** review, **⇧⌘S** export, **⌘Z** undo, **⇧⌘Z** redo.

## Map and villager scope

This is a partial NHSE port. Player Settings and Storage currently edit the primary human resident only; appearance, additional-player editing, storage-capacity upgrades, inventory-file import/export, progression flags, recipes, reactions, house interiors, and NHSE's other advanced editors are not included. Supporting other residents' files for identity propagation does not expose their settings for editing.

The map is a schematic view of the save layers; river/cliff/path edge shapes are summarized by color. Base shoreline acres and custom-design data are preserved. The editor does not automatically solve terrain adjacency, path edges, collisions, bridge/incline connections, building footprints, or inaccessible placements. Review your layout before importing it.

Choosing a villager changes their identity and applies the default personality and catchphrase. Existing house, furniture, move-in progress, and player memories are retained. This is not a full house/preset replacement. Human player hair, face, skin, or other appearance editing is not included.

## Build and test

Requires Xcode 16 or later (Swift 6 toolchain and macOS SDK). No package downloads required.

```sh
cd macOS
swift test --scratch-path /private/tmp/ACNH-Mac-Tests --disable-sandbox
ACNH_BUILD_SCRATCH=/private/tmp/ACNH-Mac-Build ACNH_BUILD_OUTPUT=/private/tmp/ACNH-Mac-App ./scripts/build-app.sh
open "/private/tmp/ACNH-Mac-App/ACNH Save Editor.app"
```

Use `./scripts/build-app.sh native` to build only for the current Mac. Open `Package.swift` in Xcode to edit the project. The original Switch source and build stay in the repository root.

For folders managed by a file provider that adds Finder metadata to generated bundles, set `ACNH_BUILD_SCRATCH` to a non-synced temporary build directory and `ACNH_BUILD_OUTPUT` to a temporary output folder. For example, `ACNH_BUILD_SCRATCH=/private/tmp/ACNH-Build ACNH_BUILD_OUTPUT=/private/tmp/ACNH-App ./scripts/build-app.sh`. The source stays in the project folder.

The source for this native port is under GPL-3.0; original MIT notices are retained. See `THIRD-PARTY-NOTICES.md` and `LICENSE`.
