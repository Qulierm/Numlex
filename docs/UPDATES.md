# Updates

Numlex updates itself in place with [Sparkle](https://sparkle-project.org)
2.9.6. This document describes the `main`-branch behaviour; a released build
may lag behind it, and every build states what it can do.

## How an update happens

1. Numlex reads the appcast at <https://numlex.tech/appcast.xml> (HTTPS only).
2. If the feed announces a newer version, Sparkle shows its standard update
   alert with the release notes.
3. The archive (a version-pinned `.dmg`) is downloaded and its **EdDSA
   (Ed25519) signature is verified before extraction** — a modified or
   corrupted archive never reaches the installer.
4. Sparkle's standard installer replaces the app and relaunches it.

There is no custom updater window and no silent background install: the
interface is Sparkle's own.

## Checking manually

- **Numlex menu → Check for Updates…** (directly under About).
- **Settings → General → Updates → Check for Updates…**.

Both entries drive the same standard check and are disabled while Sparkle is
busy or when this build cannot update (see below).

## Automatic checks

- **Settings → General → Updates → Automatically check for updates.**
- The preference belongs to Sparkle's own `UserDefaults` — it is never copied
  into Numlex's settings store or `.nlx` exports.
- Scheduling follows Sparkle's defaults (a check every 24 hours, with
  Sparkle's own permission prompt on the second launch). Numlex never forces a
  check on every launch.

## Privacy

Updating adds exactly two HTTPS requests, and only when an update is checked
or installed:

| Request | When | What is sent |
| --- | --- | --- |
| `https://numlex.tech/appcast.xml` | A check (manual or scheduled) | Nothing identifying — a plain GET |
| `https://github.com/Qulierm/Numlex/releases/download/<version>/<file>.dmg` | Only when an update is accepted | Nothing identifying — a plain GET of the version-pinned asset |

Anonymous system profiling is disabled (`SUEnableSystemProfiling = false`), and
the app sends no identifiers, no analytics and no usage data. Offline, or if
the feed cannot be read, Sparkle reports the failure in its standard alert and
the app keeps working.

## First updater-enabled release

4.7.0 has no updater and cannot gain one retroactively. The bootstrap feed
therefore advertises 4.7.0 itself: an updater-enabled build reports "up to
date" instead of an error. Existing 4.7 users install the **first
updater-enabled release manually once**; every release after that updates
in-app.

## What a build can do

| Situation | Behaviour |
| --- | --- |
| Packaged `.app` with feed + public key | Updates enabled |
| `swift run Numlex` (no bundle metadata) | Menu item disabled, Settings explains why, no crash |
| Missing/invalid feed URL or public key | Same graceful disable with a typed reason |
| Feed unreachable / 404 / malformed | Sparkle's standard error, no partial install |
| Read-only install location or App Translocation | Sparkle's standard relocate/continue flow |

## Code signing is part of the install check

Sparkle verifies that the downloaded app is signed with the **same Apple code
signing identity** as the installed app. Consequences:

- An **ad-hoc signed** build (the current default for local builds) can check,
  verify and download, but Sparkle rejects the install with a signature
  mismatch — ad-hoc signatures have `cdhash`-based requirements that never
  match a different build.
- In-app installation therefore requires a **stable signing identity** for
  every release, supplied through `NUMLEX_SIGN_IDENTITY` at build time (for
  example the maintainer's `Apple Development` identity locally, or a
  distribution identity for public builds). Both the installed and the new
  build must use the same identity.
- The EdDSA archive signature is mandatory in every case; it is what proves
  the download itself.

## Signing key

- One Ed25519 key pair lives in the maintainer's **login Keychain**
  (Sparkle's `generate_keys`). Only the base64 **public** key is committed
  (`SUPublicEDKey` in `Sources/NumlexApp/Resources/Info.plist`).
- The private key is never committed, never printed and never exported
  automatically.
- **Manual backup** (run deliberately, then store offline and delete the
  plaintext copy):

  ```sh
  .build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/Desktop/numlex-sparkle-private-key.txt
  ```

  Losing this key is serious: without a stable Apple signing identity as a
  fallback, future updates could no longer be verified. Keep the backup safe.

## Release workflow

1. Build and package: `Scripts/build-app.sh release`
   (embeds and signs `Sparkle.framework`, asserts the pinned version).
2. Build the DMG and upload it as a **new, immutable** release asset.
3. Generate and sign the feed entry for that exact asset:

   ```sh
   Scripts/prepare-update-feed.sh \
     --dmg /path/to/Numlex-<version>-macOS-arm64.dmg \
     --version <version> \
     --download-url-prefix https://github.com/Qulierm/Numlex/releases/download/<version>/
   ```

   The script fails closed if the tool/key/DMG/version is missing, if the URL
   looks mutable (no `latest`), or if the signature does not verify. It writes
   `appcast.xml` atomically and prints the archive SHA-256.
4. Commit the new `public/appcast.xml` in the website repository and deploy.
5. Verify the live feed (see below).

Rules:

- **Published assets are immutable.** Never re-upload, replace, retag or delete
  a released archive to fix a feed — publish a new version instead.
- Publish the feed **after** the asset exists; a feed must never point at a
  URL that is not yet downloadable.
- The enclosure URL must be **version-pinned**; `latest` URLs are rejected by
  the tooling.
- Delta updates are not produced (full DMG only).

Validation helpers:

```sh
Scripts/validate-appcast.sh public/appcast.xml --archive <path-to-dmg> \
  --expect-version <version> --expect-min-os 26.0
```

The validator checks the XML shape, version, HTTPS version-pinned enclosure
URL, exact length, minimum system version and the EdDSA signature
(cryptographically, with the committed public key). A corrupted archive must
fail.

## Homebrew

The project's own cask is updated at release time for the first
updater-enabled release to set `auto_updates true`, so Homebrew stops treating
the app as version-managed. This is a release-time change; the tap is not
touched by this documentation round.
