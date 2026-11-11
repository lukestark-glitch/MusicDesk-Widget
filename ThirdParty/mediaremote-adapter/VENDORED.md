# Vendored: mediaremote-adapter

| | |
|---|---|
| Upstream | https://github.com/ungive/mediaremote-adapter |
| Commit | `0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd` (2026-10-17) |
| Vendored on | 2026-11-11 |
| License | BSD 3-Clause (`LICENSE`, also in `/LICENSE-THIRD-PARTY.md`) |

## What was copied

Unmodified: `CMakeLists.txt`, `LICENSE`, `README.md`, `bin/`, `include/`, `src/`.
Left out: `scripts/` (README badge tooling, dev helper), `Makefile`,
editor/format configs (`.vscode/`, `.clang-format`, `.cmake-format`,
`.perltidyrc`), `.gitignore`, `.gitmodules`.

No local patches. To update: replace the files above with a newer upstream
checkout and update the commit/date in this file.

## How MusicDesk uses it

`scripts/build.sh` builds `MediaRemoteAdapter.framework` and
`MediaRemoteAdapterTestClient` with CMake (Release, `arm64;x86_64`,
deployment target 13.0) into `.build/adapter` and copies them into the app:

- `Contents/Resources/mediaremote-adapter.pl`
- `Contents/Frameworks/MediaRemoteAdapter.framework`
- `Contents/Helpers/MediaRemoteAdapterTestClient`

At runtime `SystemNowPlayingSource` runs
`/usr/bin/perl <pl> <framework> <test client> stream --micros --no-artwork --debounce=50`
(plus `test`, `send <id>`, `seek <micros>` as short-lived processes).
`/usr/bin/perl` is a platform binary that is entitled to read MediaRemote,
which is why the adapter works on macOS 15.4+ where apps can no longer call
MediaRemote directly.

## Why upstream and not the ejbills fork

The ejbills fork (used by some Swift packages) was evaluated and rejected:

- Upstream provides the documented CLI `stream` / `get` / `send` / `seek` /
  `test`, including the `MediaRemoteAdapterTestClient` needed for the
  self-test that drives MusicDesk's automatic fallback.
- The fork changes the CLI to a `loop`/`get` model and locates its resources
  via `Bundle.module` / `Bundle(for:)`. Those paths break in MusicDesk's
  hand-assembled SPM app bundle (no Xcode project, resources copied by
  `scripts/build.sh`), whereas upstream takes absolute paths as arguments.
