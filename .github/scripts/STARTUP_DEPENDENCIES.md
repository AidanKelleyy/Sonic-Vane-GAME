# Player startup dependencies

The platform base presets must contain script classes and static preload resources before Shared, Characters, Objects, or level packs mount. A later pack cannot reliably repair a script class that already failed to parse.

`build.py` synchronizes Windows, Linux, and macOS base selections before any export. The validator follows player scripts, selected bootstrap scripts, autoloads, global script classes, path-based inheritance, literal preloads, and text-resource dependencies. Script UID preloads resolve through their source `.uid` files. Missing files, unresolved static UIDs, excluded dependencies, or stale generated metadata fail validation. Dynamically constructed `load()` paths remain runtime concerns.

Run from the repository root:

```sh
python .github/scripts/validate_startup_dependencies.py --fix
python .github/scripts/validate_startup_dependencies.py
python -m unittest discover -s .github/scripts/tests
```

The first command updates the base lists and `LS5Framework/Resources/Diagnostics/PlayerStartupDependencies.json`. The second validates without changing files. Run both before exporting directly through Godot; the release build script runs them automatically. The raw JSON manifest is explicitly included in every platform preset.

After exporting an executable for the host operating system, `build.py` runs its packaged startup verifier in an empty working directory before staging Data packs or archives. Every player script must load and support instantiation from the base package. Missing result markers, script errors, failed checks, and process failures stop packaging. Results are saved under the build output's `validation` directory. Other platform selections receive the same dependency validation; their binaries require their native operating system for execution.

The runtime diagnostic checks manifest resources before the main menu mounts packs. Missing bootstrap resources remain a confirmed `PLAYER_SCRIPT_FAILED` condition until restart. Character spawning validates player scripts and attached scene scripts, rejects an inert character root, and preserves an existing player when a character replacement fails validation. Existing scene/dependency logs retain the failed references and their owners. The diagnostic itself uses native types and has no dependency on PlayerController or its ability classes.

Backspace toggles the diagnostic window through the `scene_diagnostics_toggle` input action. The binding is available in both menus under Controls > Debug. Hidden reports continue updating and logging; refreshes preserve the hidden state. Text entry and input rebinding retain their normal Backspace behavior. Hiding an active inspection restores its prior pause state and focus. Explicitly opening dependency inspection makes a hidden report visible.
