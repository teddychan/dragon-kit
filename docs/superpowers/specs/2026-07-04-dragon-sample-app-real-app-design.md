# Dragon Sample App — turn the DragonKit Example into a real, releasable app

**Date:** 2026-07-04
**Status:** Approved design → implementation planning
**Scope:** 5 repos (`dragon-release-ci`, `dragon-kit`, `homebrew-tap`, `www.dragonapp.com`, `clipmenu-2`)

## Motivation

The DragonKit `Example/` app ("DragonKit Sample") is a reference that wires up every
kit module, but it is not a *real* app: it has no stable local identity (TCC grants
don't survive rebuilds and a local build would collide with any installed copy), and
no release path (can't be `brew install`-ed). Making it a genuine, shippable Dragon
app also makes `Example/` a complete reference for the **release pipeline** itself —
the one part of the Dragon-app story the kit didn't yet demonstrate.

## Locked decisions (from brainstorming)

| Decision | Choice |
|---|---|
| App display name | **Dragon Sample App** (local debug: **Dragon Sample App Debug**) |
| Bundle id | **`com.dragonapp.dragon-sample-app`** (debug: `…dragon-sample-app.debug`) |
| Homebrew cask | **`dragon-sample-app`** → `brew install --cask teddychan/tap/dragon-sample-app` |
| Release trigger | **`sample-v*`** tags on `dragon-kit` (never `v*`, which is the SwiftPM library version) |
| Release host | GitHub Releases on **`dragon-kit`** itself |
| Pipeline | **Generalize the shared `dragon-release-ci`** swiftpm front-end (backward-compatible), not a fork |
| Local build identity | Separate **`.debug`** identity + **stable self-signed cert** so grants persist |
| Publish scope | Full reference pipeline; actual release gated on user-supplied secrets + a pushed tag |

## Repo-by-repo changes

### 1. `dragon-release-ci` — generalize the swiftpm front-end (cut `v3`)

Only the **Assemble .app bundle [swiftpm]** step hardcodes ClipMenu. Everything else
(sign, notarize, zip via `zip_name_template`, appcast via `app_slug` +
`swiftpm_working_directory`, cask bump) is already generic.

Add two optional inputs, defaulting to ClipMenu's current values (so ClipMenu is
byte-for-byte unaffected):

- `swiftpm_product_name` — string, default `ClipMenu`. The `swift build` product /
  executable name copied into `Contents/MacOS/`.
- `swiftpm_app_name_template` — string, default `ClipMenu {MAJOR}`. Tokens `{MAJOR}`,
  `{VERSION}`. Rendered → `APP_NAME` (the `.app` filename + `CFBundleName` /
  `CFBundleDisplayName`).

Assemble step edits:
- `APP_NAME` ← template with `{MAJOR}`/`{VERSION}` substituted (was `"ClipMenu ${MAJOR}"`).
- `cp "$BIN_PATH/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"` (was hardcoded `ClipMenu`).
  `CFBundleExecutable` in the app's `Info.plist` must equal `swiftpm_product_name`.
- `cp AppIcon.icns` becomes conditional: `[ -f AppIcon.icns ] && cp …` (ClipMenu has
  one; the sample defers a custom icon → default icon).
- Leave `CLIPMENU_SPARKLE` env var as-is (ClipMenu's `Package.swift` reads it; the
  sample always links Sparkle via `DragonKitUpdates`, so it ignores the var — the
  Sparkle.framework presence check still passes).

Tag the generalized workflow **`v3`**. Implementation must re-read the **sign** step to
confirm it signs `$APP` (not a hardcoded binary path) — grep shows no ClipMenu there,
to be verified.

### 2. `clipmenu-2` — bump caller `@v2` → `@v3`

Change only `uses: …release-macos.yml@v2` → `@v3` in `.github/workflows/release.yml`.
No new `with:` inputs (defaults reproduce current behavior). This is the regression
gate: a dry review + (ideally) a `workflow_dispatch` test proving ClipMenu still builds
"ClipMenu N.app" identically.

### 3. `dragon-kit` — rename/restructure `Example/` + add the release caller

- **Rename** "DragonKit Sample" → "Dragon Sample App" and bundle id
  `com.dragonapp.dragonkit-sample` → `com.dragonapp.dragon-sample-app` across:
  `AppDelegate.appName`, `SettingsModel.suiteName` (derive from / match the new id),
  `Info.plist` (`CFBundleName`, `CFBundleDisplayName`, `CFBundleIdentifier`), the 7
  `Localizable.strings` hints mentioning the old name, `README.md`, and `run.sh`.
- **Restructure for `build_kind: swiftpm`:** move `Example/Resources/Info.plist` →
  `Example/Info.plist` (working-dir root, matching clipmenu's layout). Keep
  `CFBundleExecutable` = the SwiftPM product name (currently `DragonAppTemplate`;
  optionally rename the product to `DragonSampleApp` for cleanliness — if renamed,
  update `Package.swift`, `run.sh`, and `CFBundleExecutable` together).
- **Sparkle metadata:** add `SUPublicEDKey` (reuse the shared EdDSA public key from
  clipmenu-2's `Info.plist`) and point `SUFeedURL` →
  `https://www.dragonapp.com/dragon-sample-app/appcast.xml`.
- **Entitlements:** add `Example/DragonSampleApp.entitlements` (hardened-runtime
  baseline; NO iCloud — that's clipmenu-specific). Not passed as
  `swiftpm_icloud_entitlements_path`; the shared workflow signs local-only by default.
- **`.github/workflows/release.yml`:** thin caller of
  `dragon-release-ci/.github/workflows/release-macos.yml@v3`, `secrets: inherit`,
  `permissions: contents: write`, trigger `sample-v*` + `workflow_dispatch`. Inputs:
  `build_kind: swiftpm`, `app_slug: dragon-sample-app`,
  `swiftpm_working_directory: Example`, `swiftpm_product_name: <product>`,
  `swiftpm_app_name_template: 'Dragon Sample App'`, `swiftpm_sparkle: true`,
  `swiftpm_runner: macos-26`, `zip_name_template: 'DragonSampleApp-{TAG}.zip'`,
  `generate_appcast_glob: swiftpm`, `bot_name: Dragon Sample Release Bot`,
  `release_title_prefix: ''`.
- **`Example/scripts/run.sh`** (§3b below).

### 3b. `dragon-kit` — stable, collision-free local build (`run.sh`)

Per the `dragon-mac-ops` convention: assemble, then re-id the bundle as
**"Dragon Sample App Debug"** / `com.dragonapp.dragon-sample-app.debug` (main bundle
only) before signing. To make the Accessibility grant **persist across rebuilds**
(ad-hoc re-prompts every build — documented caveat), sign with a **stable self-signed
identity** named e.g. `Dragon Sample App Debug` if present in the login keychain;
else fall back to ad-hoc and print a note on how to create the cert once. Quit any
running debug instance, then launch.

### 4. `homebrew-tap` — add the cask

`Casks/dragon-sample-app.rb`, modeled on `clipmenu-2.rb`:
- `app "Dragon Sample App.app"`, `homepage "https://www.dragonapp.com/"`,
  `auto_updates true`, `depends_on macos: :tahoe`.
- `url` → `https://github.com/teddychan/dragon-kit/releases/download/sample-v#{version}/DragonSampleApp-sample-v#{version}.zip` (exact string reconciled with the resolved `zip_name_template`).
- `zap trash:` the 4 standard paths for `com.dragonapp.dragon-sample-app`
  (Application Support, Caches, HTTPStorages, Preferences plist).
- `version`/`sha256` are placeholders the release CI overwrites on first publish.

### 5. `www.dragonapp.com` — appcast slot

Add `docs/dragon-sample-app/appcast.xml` as an empty seed the CI overwrites on
release. **No marketing page** (SEO skill not triggered — no new user-facing page).

## Ordering & dependencies

1. `dragon-release-ci`: generalize + tag `v3` (must exist before any caller references it).
2. `clipmenu-2`: bump caller `@v3`; verify no ClipMenu regression.
3. `www.dragonapp.com`: appcast seed dir (so the first release has a push target).
4. `homebrew-tap`: cask skeleton.
5. `dragon-kit`: rename/restructure + `release.yml` + `run.sh`.

Each repo change lands via its own **branch → PR → merge** (PR-first flow). Tags
(`v3`, `sample-v1.0.0`) are pushed after the relevant PRs merge.

## Secrets & manual steps (user-only — hard blockers to a working release)

Add to **`dragon-kit`** repo Actions secrets (same set clipmenu-2 uses; copy over):
`DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `NOTARY_KEY_P8_BASE64`,
`NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `SPARKLE_EDDSA_PRIVATE_KEY`, `PUBLIC_RELEASE_TOKEN`.
Then push **`sample-v1.0.0`** to cut the first release. Optionally create the local
self-signed `Dragon Sample App Debug` cert for persistent local grants.

## Testing & verification

- **dragon-release-ci:** YAML lint; diff proving only the assemble step changed;
  confirm defaults reproduce ClipMenu's `APP_NAME`/binary path.
- **clipmenu-2:** caller diff is one line; `workflow_dispatch` (or next real tag)
  builds "ClipMenu N.app" unchanged.
- **dragon-kit:** `swift build` in `Example/` still succeeds; `run.sh` produces
  "Dragon Sample App Debug.app" with the `.debug` id and launches; existing
  `swift test` (23) still green; localization key-parity test still passes.
- **cask:** `brew audit --cask` (style) on the skeleton.
- **End-to-end:** after secrets + `sample-v1.0.0`, CI produces a notarized zip,
  overwrites the appcast, bumps the cask; `brew install --cask teddychan/tap/dragon-sample-app`
  installs a launchable, notarized app.

## Risks & mitigations

- **ClipMenu release regression (highest).** Mitigation: backward-compatible inputs
  (defaults == current values); one-line caller bump; verify via dispatch before
  relying on it for a real ClipMenu release.
- **Unknown hardcoding in the sign/appcast steps.** Mitigation: re-read those steps
  during implementation; grep already shows ClipMenu only in the assemble step.
- **`zip_name_template` ↔ cask `url` mismatch.** Mitigation: derive the cask `url`
  from the exact resolved zip name; the CI cask-bump is the source of truth after
  first publish.
- **Product rename churn.** Mitigation: renaming the SPM product `DragonAppTemplate`
  → `DragonSampleApp` is optional; if skipped, pass `swiftpm_product_name: DragonAppTemplate`
  and keep `CFBundleExecutable` as-is.

## Out of scope (YAGNI)

Custom app icon (default icon ships), a marketing page, and a Mac App Store variant.
DragonBackup folder-backup generalization remains separately deferred (see README roadmap).
