# Release assets

Public macOS release artifacts and the Sparkle appcast for Vibes.

## Layout

```text
release/
  README.md            this file
  appcast/
    appcast.xml        tracked public feed snapshot, regenerated per release
    Vibes-<ver>.zip    staged update archive (NOT committed — gitignored)
    <ver>.md           staged release notes copy (NOT committed)
  release-notes/
    0.2.0.md           source release notes, one file per version (committed)
build/
  Vibes-<ver>.dmg      generated first-download DMG (NOT committed)
  SHA256SUMS           generated checksums (NOT committed)
  latest.json          generated public latest manifest (NOT committed)
```

## How a release flows

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Write `release/release-notes/<version>.md`.
3. `cp .env.release.example .env.release` and fill it in. Set
   `VIBES_RELEASE_VERSION` to the same value as `MARKETING_VERSION`, set
   `VIBES_BUILD_NUMBER` to the same value as `CURRENT_PROJECT_VERSION`, and use
   `VIBES_APPCAST_BASE_URL=https://vibes.opentangle.com/downloads`.
4. Confirm `.env.deploy` includes explicit `DEPLOY_USER`, `DEPLOY_HOST`,
   `DEPLOY_PATH`, and `DEPLOY_DOMAIN`.
5. `make mac-release` — builds, signs, notarizes, staples, packages the update
   zip and first-download DMG, regenerates the appcast, writes
   `build/latest.json`, and publishes the release.
6. Open `https://vibes.opentangle.com/download`, install the DMG, then run
   old-version-to-new-version Sparkle QA from an older signed build.

The `mac-release` target runs the same steps directly:

```bash
VIBES_BUILD_DMG=1 scripts/release-mac.sh
scripts/generate-appcast.sh
scripts/publish-mac-release.sh
```

`scripts/publish-mac-release.sh` generates the public latest manifest from the
release environment and uploads it to `/downloads/latest.json`. It also writes
`build/SHA256SUMS`, uploads `/downloads/SHA256SUMS`, installs immutable
`/downloads/Vibes-<ver>.dmg` and `/downloads/Vibes-<ver>.zip`, atomically
repoints `/downloads/Vibes.dmg`, publishes `/appcast.xml`, and smoke-checks the
public URLs. Do not edit `latest.json` or `SHA256SUMS` manually.

Public URL model:

- `/download` — website download page.
- `/downloads/Vibes.dmg` — stable latest first-download DMG.
- `/downloads/Vibes-<ver>.dmg` — immutable versioned DMG.
- `/downloads/Vibes-<ver>.zip` — immutable Sparkle update archive.
- `/appcast.xml` — Sparkle appcast.
- `/downloads/latest.json` — generated public manifest.
- `/downloads/SHA256SUMS` — generated checksums.

Commit `release/appcast/appcast.xml` only as the canonical public feed snapshot
that should be installed at `/appcast.xml`. Do not commit the other generated
appcast staging outputs: update zips, DMGs, deltas, HTML output, or copied
release notes under `release/appcast/`. Built archives, checksums, and
`build/latest.json` are also gitignored. See `docs/client-runbook.md` for full
instructions and troubleshooting.

## Never commit

Private keys, exported certificates, notarization passwords/API keys,
Sparkle EdDSA private keys, `.xcarchive`, `.dmg`, `.zip`, or `.env.release`.
