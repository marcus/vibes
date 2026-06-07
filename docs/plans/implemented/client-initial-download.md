# Vibes macOS initial download plan

## Decision

Host the initial Mac download on `https://vibes.opentangle.com` alongside the existing website and Sparkle appcast. For a small direct-distribution macOS app, self-hosting the DMG and update zip is normal and simpler than introducing GitHub Releases as a second public surface. GitHub Releases remains a fine fallback if bandwidth, release history, or mirroring becomes useful later.

Use this hosting model:

- Website download button: `https://vibes.opentangle.com/download`
- Stable latest DMG URL: `https://vibes.opentangle.com/downloads/Vibes.dmg`
- Immutable versioned DMG URL: `https://vibes.opentangle.com/downloads/Vibes-<version>.dmg`
- Stable appcast URL: `https://vibes.opentangle.com/appcast.xml`
- Immutable update zip URL: `https://vibes.opentangle.com/downloads/Vibes-<version>.zip`

The DMG is for first install. The zip is for Sparkle updates. Both come from the same signed, notarized, stapled `Vibes.app` bundle produced by `scripts/release-mac.sh`.

## Current repo facts

- Sparkle is implemented and `SUFeedURL` is already `https://vibes.opentangle.com/appcast.xml`.
- `scripts/release-mac.sh` stages `release/appcast/Vibes-<version>.zip`.
- `scripts/release-mac.sh` builds `build/Vibes-<version>.dmg` when `VIBES_BUILD_DMG=1`.
- `scripts/generate-appcast.sh` generates `release/appcast/appcast.xml` using `VIBES_APPCAST_BASE_URL`.
- `deploy/nginx.conf.template` currently proxies all paths to the SvelteKit server.
- `scripts/deploy-server.sh` currently deploys server source only; it does not upload release binaries or static appcast files.

## Why self-hosting is acceptable here

Self-hosting is the pragmatic v1 path because:

- The audience is small.
- The app binaries should be small.
- The domain already exists.
- Sparkle only needs stable HTTPS URLs.
- The release flow can stay one command from the maintainer's Mac, where Developer ID, notarization, and Sparkle private keys already live.

The main tradeoff is operational: the VPS now serves static binaries, so nginx must handle file size, MIME types, cache headers, and enough disk space. Avoid routing downloads through SvelteKit/Node.

## Target server layout

Create a static release directory outside the server source tree:

```text
/var/www/vibes/
  server/                  SvelteKit relay source/build
  data/                    SQLite and server data
  releases/
    appcast.xml            latest Sparkle feed
    downloads/
      Vibes.dmg            stable symlink or copied latest DMG
      Vibes-0.2.0.dmg      immutable first-download artifact
      Vibes-0.2.0.zip      immutable Sparkle update artifact
      SHA256SUMS           checksums for current published artifacts
```

Do not put release artifacts under `server/`. `make deploy` uses `rsync --delete` for server source and must not risk deleting binaries.

## Phase 1: nginx static download hosting

Update `deploy/nginx.conf.template` so static release files are served by nginx before the proxy:

```nginx
location = /appcast.xml {
    alias ${DEPLOY_PATH}/releases/appcast.xml;
    default_type application/xml;
    add_header Cache-Control "no-cache, must-revalidate" always;
}

location /downloads/ {
    alias ${DEPLOY_PATH}/releases/downloads/;
    types {
        application/x-apple-diskimage dmg;
        application/zip zip;
        text/plain txt;
    }
    add_header Cache-Control "public, max-age=31536000, immutable" always;
}

location = /downloads/Vibes.dmg {
    alias ${DEPLOY_PATH}/releases/downloads/Vibes.dmg;
    default_type application/x-apple-diskimage;
    add_header Cache-Control "no-cache, must-revalidate" always;
}
```

Important nginx details:

- Put these locations above `location /`.
- Keep `/appcast.xml` no-cache so Sparkle sees new releases quickly.
- Keep immutable versioned downloads cacheable.
- Keep `Vibes.dmg` no-cache because it is a stable latest pointer.
- Increase `client_max_body_size` only if uploads ever go through nginx. Plain downloads do not need it.

Bootstrap the directory during first-time deploy:

```bash
ssh "$DEPLOY_USER@$DEPLOY_HOST" "mkdir -p '$DEPLOY_PATH/releases/downloads'"
```

## Phase 2: publish script

Add `scripts/publish-mac-release.sh`. It should publish artifacts already created by `release-mac.sh` and `generate-appcast.sh`.

Inputs:

```text
DEPLOY_USER
DEPLOY_HOST
DEPLOY_PATH
DEPLOY_DOMAIN
VIBES_RELEASE_VERSION
VIBES_BUILD_DMG=1
```

Local files required:

```text
release/appcast/appcast.xml
release/appcast/Vibes-<version>.zip
build/Vibes-<version>.dmg
```

Behavior:

1. Load `.env.deploy` and `.env.release` if present.
2. Fail if required env vars are missing.
3. Fail if `VIBES_BUILD_DMG` was not `1` or the DMG is missing. The initial download must not silently publish zip-only.
4. Create local checksums:

```bash
shasum -a 256 \
  "build/Vibes-${VIBES_RELEASE_VERSION}.dmg" \
  "release/appcast/Vibes-${VIBES_RELEASE_VERSION}.zip" \
  > "build/SHA256SUMS"
```

5. Upload versioned files to a temporary remote directory:

```text
$DEPLOY_PATH/releases/.incoming/Vibes-<version>-<timestamp>/
```

6. On the remote host, atomically install:

```bash
install -m 0644 .incoming/.../Vibes-<version>.dmg releases/downloads/
install -m 0644 .incoming/.../Vibes-<version>.zip releases/downloads/
install -m 0644 .incoming/.../SHA256SUMS releases/downloads/SHA256SUMS
install -m 0644 .incoming/.../appcast.xml releases/appcast.xml
ln -sfn Vibes-<version>.dmg releases/downloads/Vibes.dmg.tmp
mv -Tf releases/downloads/Vibes.dmg.tmp releases/downloads/Vibes.dmg
```

On macOS/BSD, `mv -T` is not available locally, but this runs on the Linux VPS. If the host is not Linux, use a portable `rm && mv` with a brief non-atomic latest-link window, or copy the file instead of using a symlink.

7. Remove the incoming directory after successful publish.
8. Smoke check public URLs:

```bash
curl -fsSI "https://${DEPLOY_DOMAIN}/appcast.xml"
curl -fsSI "https://${DEPLOY_DOMAIN}/downloads/Vibes-${VIBES_RELEASE_VERSION}.zip"
curl -fsSI "https://${DEPLOY_DOMAIN}/downloads/Vibes-${VIBES_RELEASE_VERSION}.dmg"
curl -fsSI "https://${DEPLOY_DOMAIN}/downloads/Vibes.dmg"
```

9. Verify appcast points at the hosted update zip:

```bash
curl -fsS "https://${DEPLOY_DOMAIN}/appcast.xml" | grep "https://${DEPLOY_DOMAIN}/downloads/Vibes-${VIBES_RELEASE_VERSION}.zip"
```

10. Print the final URLs.

Do not commit DMGs, zips, or checksums generated for a release.

## Phase 3: one-command release target

Add a Make target that cuts and publishes a release from the maintainer's Mac:

```make
.PHONY: mac-release
mac-release:
	VIBES_BUILD_DMG=1 scripts/release-mac.sh
	scripts/generate-appcast.sh
	scripts/publish-mac-release.sh
```

Expected `.env.release` values for self-hosting:

```bash
VIBES_APPCAST_BASE_URL=https://vibes.opentangle.com/downloads
VIBES_BUILD_DMG=1
```

The release flow becomes:

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
2. Add `release/release-notes/<version>.md`.
3. Set `VIBES_RELEASE_VERSION` and `VIBES_BUILD_NUMBER` in `.env.release`.
4. Run `make mac-release`.
5. Open `https://vibes.opentangle.com/download` and download the DMG.
6. Run the Sparkle old-version-to-new-version QA from `docs/client-runbook.md`.

This is "automatic" at release time without putting Apple signing, notarization, and Sparkle private keys into CI. Add CI later only if manual release work becomes a real bottleneck.

## Phase 4: website download page

Add a public download page in SvelteKit:

```text
server/src/routes/download/+page.svelte
```

Page behavior:

- Primary button downloads `/downloads/Vibes.dmg`.
- Secondary text shows the current version from a checked-in or generated public manifest.
- Include a short macOS requirement line: macOS 14 or newer.
- Include a small note that the app is Developer ID signed and notarized.
- Include a checksum link to `/downloads/SHA256SUMS`.
- Keep the page visually aligned with existing Vibes style tokens.
- No analytics beyond normal server logs in v1.

Avoid a big marketing page. The first viewport should make the product name and download action obvious.

Recommended minimal copy:

```text
Vibes for Mac
Private ambient presence for small coding groups.

Download for macOS
macOS 14 or newer. Signed and notarized.
```

## Phase 5: release manifest

Add a tiny public manifest so the website can show the current version without parsing the Sparkle appcast in SvelteKit:

```text
release/latest.json
```

Example:

```json
{
  "version": "0.2.0",
  "build": 2,
  "minimumMacOS": "14.0",
  "dmg": "/downloads/Vibes.dmg",
  "versionedDmg": "/downloads/Vibes-0.2.0.dmg",
  "zip": "/downloads/Vibes-0.2.0.zip",
  "appcast": "/appcast.xml",
  "sha256": "/downloads/SHA256SUMS",
  "publishedAt": "2026-06-07T00:00:00Z"
}
```

Publish it to:

```text
https://vibes.opentangle.com/downloads/latest.json
```

Then `server/src/routes/download/+page.server.js` can fetch or import this manifest. Simpler v1 option: the page can link to `/downloads/Vibes.dmg` without showing an exact version, and the manifest can be added later. Prefer the manifest if the agent is already touching publish automation.

## Phase 6: appcast and initial download consistency

The initial DMG and Sparkle update zip must come from the same release build.

The publish script should verify:

- `build/Vibes-<version>.dmg` exists if publishing a first-download release.
- `release/appcast/Vibes-<version>.zip` exists.
- `release/appcast/appcast.xml` contains `Vibes-<version>.zip`.
- The appcast zip URL uses `https://vibes.opentangle.com/downloads/`.
- The appcast build number matches `VIBES_BUILD_NUMBER`.
- The DMG and zip are newer than the last git commit touching `client/` or `release/release-notes/<version>.md`, or the script prints a warning.

Do not generate separate app bundles for DMG and zip. That creates avoidable signing and version drift.

## Phase 7: rollback

Rollback should be explicit and boring:

1. Keep older versioned DMGs and zips on the host.
2. To rollback first downloads, repoint `downloads/Vibes.dmg` at the older DMG.
3. To rollback Sparkle, publish an appcast that no longer advertises the bad version or advertises a newer fixed build. Sparkle generally will not downgrade users to a lower build number.
4. If a bad release has already been installed, cut a higher `CURRENT_PROJECT_VERSION` hotfix rather than trying to force a downgrade.

Document the exact rollback commands in `docs/client-runbook.md` when implementing the publish script.

## Phase 8: verification

Implementation is done only when:

- `make server-check` passes if the website download page changed.
- `make client` passes if release scripts or Xcode settings changed.
- `VIBES_BUILD_DMG=1 scripts/release-mac.sh` produces a notarized DMG.
- `scripts/generate-appcast.sh` produces an appcast whose zip URL is under `https://vibes.opentangle.com/downloads/`.
- `scripts/publish-mac-release.sh` uploads the DMG, zip, appcast, and checksums to the host.
- `curl -I https://vibes.opentangle.com/downloads/Vibes.dmg` returns `200` and a plausible disk image content type.
- `curl -I https://vibes.opentangle.com/appcast.xml` returns `200` and no-cache headers.
- Downloading the public DMG, opening it, dragging Vibes to `/Applications`, and launching the app works without Gatekeeper warnings beyond the normal first-launch confirmation.
- An older installed Vibes build can update through Sparkle using the public appcast.
- The handoff includes the published URLs and command output for the curl checks.

## Future automation option

If releases become frequent, add a GitHub Actions workflow triggered by `v*` tags:

- Build on `macos-latest`.
- Sign with imported Developer ID certificate stored as GitHub secret.
- Notarize with App Store Connect API key secrets.
- Sign appcast with an encrypted Sparkle EdDSA key file.
- Upload via SSH deploy key to `vibes.opentangle.com`.

Do not start there. For this app and audience, a local `make mac-release` is lower risk because the private Apple and Sparkle credentials stay on the maintainer's Mac.
