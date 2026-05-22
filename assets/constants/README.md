# Constants Mirror

This directory contains JSON mirrors of the shared constants defined in `crates/firewolf-shared/src/constants/`.

## Why this exists

Per ADR-037 and the decision register, tunables are split into two surfaces:
1. **Hot-path constants**: Live as Rust `pub const` for performance and type safety.
2. **JSON-overridable tunables**: Live in this directory as JSON files.

These JSON files mirror the default values of the Rust constants. They exist to provide a target schema for mod authors and to supply the future Ring 1 mod loader with baseline data to merge against.

## Override Semantics

Ring 1 (data) mods can override these values using the `constants_overrides` field in their `mod.json` manifest. The keys in the manifest are dotted paths corresponding to the file and constant name (e.g., `movement.WALK_SPEED`).

For more details on the mod manifest schema, see `assets/mods/schemas/mod.schema.json` and the example in `assets/mods/sample/mod.json`.

**Note:** Runtime override merging and hot-reloading are not yet implemented. This directory currently serves only as a static schema target.
