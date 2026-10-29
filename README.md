# NHSE for Mac

A native SwiftUI Animal Crossing: New Horizons save editor for macOS, primarily adapted from [NHSE](https://github.com/kwsch/NHSE). The initial foundation and selected save-cryptography routines come from [ACNH-Save-Editor](https://github.com/cbreezy210/ACNH-Save-Editor).

Current Mac version: **1.4.1**. Requires **macOS 14 or later**. Universal builds support Apple silicon and Intel. Supported save revisions: **ACNH 3.0.0–3.0.3**.

## Features

- Player settings: primary resident name and birthday.
- Island settings: island name, hemisphere, airport, weather, fruit, and flowers.
- Pockets and home storage with bundled item icons, item search, quantities, and multiple-slot placement. Shift-click selects a range; Command-click adds or removes individual slots.
- Island map editing for terrain, paths, outdoor items, and building positions.
- Animal-villager identities, personality, catchphrases, moving-out state, and basic friendship.
- Money editing, saved pocket loadouts, undo/redo, change review, full-save exports, verified backups, and restore.

This is a partial NHSE port. Read the [Mac guide](ACNH-Save-Editor/macOS/README.md) for supported settings and limitations. Edits target the primary resident; unlocked inventory capacity and locked records are preserved.

## Build and test

The Mac app uses Swift Package Manager and Xcode's Swift toolchain. No third-party runtime is required.

```sh
cd ACNH-Save-Editor/macOS
swift test --scratch-path /private/tmp/NHSE-Mac-Tests --disable-sandbox
ACNH_BUILD_SCRATCH=/private/tmp/NHSE-Mac-Build ACNH_BUILD_OUTPUT=/private/tmp/NHSE-Mac-App ./scripts/build-app.sh
open "/private/tmp/NHSE-Mac-App/ACNH Save Editor.app"
```

Using a local build folder avoids file-provider metadata interfering with app signing in cloud-synced workspaces. Builds are ad-hoc signed, not notarized.

## Save files and validation

Open a complete exported save folder containing `main.dat`, `mainHeader.dat`, and the resident files. Review your draft, then export an edited copy or save with an automatic backup. Keep a separate original backup and import saves with the game closed.

**55 automated tests passed** for version 1.4.1, alongside native interface and independent export checks. See the [validation report](ACNH-Save-Editor/macOS/VALIDATION.md). Importing the edited save back into the game remains untested.

Personal save files, build caches, and packaged application bundles are excluded from this repository.

## Source and credits

[NHSE](https://github.com/kwsch/NHSE) is the primary reference for save structures, player and island settings, map and villager editing, home storage, item metadata, and bundled inventory artwork. [ACNH-Save-Editor](https://github.com/cbreezy210/ACNH-Save-Editor) provided the original foundation and reused encryption and hashing routines. The Mac interface and save-management workflows are implemented natively in SwiftUI.

- [Native Mac source and guide](ACNH-Save-Editor/macOS/README.md)
- [Original Switch source](ACNH-Save-Editor/README.md)
- [Third-party notices and provenance](ACNH-Save-Editor/macOS/THIRD-PARTY-NOTICES.md)

The native Mac port is **GPL-3.0**; see [LICENSE](LICENSE). Original MIT portions retain their [upstream license](ACNH-Save-Editor/LICENSE). Nintendo artwork and trademarks belong to their respective rights holders. This project is unaffiliated with Nintendo and is not an official NHSE release.
