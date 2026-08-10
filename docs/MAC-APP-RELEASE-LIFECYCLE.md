# Dragon macOS app release lifecycle

**Status:** Accepted

**Applies to:** Every Dragon macOS app

**Decision date:** 2026-08-10

This is the canonical release process for Dragon macOS apps. It defines the boundary between
local development, a public app release, and the marketing site so those three concerns cannot
silently acquire competing version numbers or block one another.

## The model

There is one public release channel. During development, the local Debug build uses the version
planned for the *next* public release; `Debug` identifies its build configuration, not a separate
version lineage.

| Concern | Identity |
|---|---|
| Latest public app | Published `vX.Y.Z` with the release bundle identifier |
| Local Debug build | Next candidate `vA.B.C Debug` with the `.debug` bundle identifier |
| Next public app | The same candidate becomes `vA.B.C` after all tests pass |
| Marketing site | Its own commit/deployment revision; it displays published app releases |

A Debug build is the local, testable form of the intended next public version. It is not another
app product, an independently numbered version, a prerelease channel, or a release distributed
to users. macOS gives it a separate local bundle identity so it can run safely beside the
installed release; that is an implementation detail, not a second version stream.

## Development and release flow

```mermaid
flowchart TD
    L["Latest public release vX.Y.Z"] --> K{"What kind of change?"}
    K -->|Bug fix| PC["Choose patch candidate vX.Y.(Z+1)"]
    K -->|New features| MC["Choose minor candidate vX.(Y+1).0"]
    PC --> C["Develop the candidate"]
    MC --> C
    C --> B["Build vA.B.C Debug locally with the .debug bundle id"]
    B --> T["Run automated and hands-on tests"]

    T -->|Tests fail| F["Modify and fix the code"]
    F --> B

    T -->|All tests pass| RP["Prepare the public release"]
    RP --> N["Update What's New for vA.B.C"]
    N --> Q["Run final tests and local release preflight"]
    Q -->|Preflight fails| F
    Q -->|Preflight passes| G["Build with release identity and push public vA.B.C tag"]
    G --> V["Tag Release Gate"]

    V -->|Gate fails| F
    V -->|Gate passes| R["Sign, notarize, and publish public release"]
    R -. "Non-blocking notification" .-> W["Marketing site refreshes its changelog"]
    R --> L2["Next development cycle"]
    W --> L2
```

Choose the next candidate version before the Debug loop. The same numeric candidate stays in use
while failed tests lead back to more development. Passing the tests removes the local Debug
presentation and `.debug` identity; it does not assign a different number. There is no Debug tag
between the previous public release and the new public tag.

## Concrete examples

### Bug-fix release

If the latest public release is `v2.10.0` and the work fixes a bug:

| Stage | User-visible version | Bundle identifier | Public? |
|---|---|---|---|
| Currently installed release | `v2.10.0` | `com.example.app` | Yes |
| Local development and testing | `v2.10.1 Debug` | `com.example.app.debug` | No |
| Release after every test passes | `v2.10.1` | `com.example.app` | Yes |

The Debug bundle's `CFBundleShortVersionString` is the numeric candidate `2.10.1`. The word
`Debug` is added by its build-channel presentation, not stored in that version field.

### New-feature release

If the latest public release is `v2.10.0` and the work adds backward-compatible features:

| Stage | User-visible version | Bundle identifier | Public? |
|---|---|---|---|
| Currently installed release | `v2.10.0` | `com.example.app` | Yes |
| Local development and testing | `v2.11.0 Debug` | `com.example.app.debug` | No |
| Release after every test passes | `v2.11.0` | `com.example.app` | Yes |

Again, `2.11.0` is selected once and tested throughout. The successful release removes the
Debug label and uses the release bundle identifier; it does not renumber the tested build.

## Public version rules

`CFBundleShortVersionString` is the sole source of truth for the app's target semantic version.
During local development it contains the next candidate number; after publication that same
number is the latest public version. It contains only `X.Y.Z`: no `v` prefix, `Debug` suffix,
prerelease suffix, or marketing-site revision belongs in it.

- The public release tag is exactly `vX.Y.Z` and must equal the bundle version.
- The user-visible `v` prefix is formatting supplied by `DragonVersion.display(_:)`.
- The Debug build adds a visible `Debug` channel label without changing the numeric candidate.
- The release build uses the same tested candidate and removes the Debug label and `.debug`
  bundle-identifier suffix.
- `CFBundleVersion` identifies the individual build and remains numeric and monotonic.
- About, What's New, update messages, diagnostics, and packaging derive the version from the
  built bundle. App code never hand-types the current version into those surfaces.
- There are no Debug tags, Debug GitHub Releases, Debug appcasts, Debug Homebrew releases, or
  Debug marketing-site events.

## Local Debug identity

Every hands-on development build visibly says `Debug`. Prefer the following local packaging:

| Field | Debug value |
|---|---|
| App display name | `<App Name> Debug` |
| Bundle name and local `.app` filename | `<App Name> Debug` |
| Bundle identifier | `<release-bundle-id>.debug` |
| Build number | Numeric `CFBundleVersion`, normally the git commit count |
| Build channel | A build setting or custom plist key such as `DragonBuildChannel = Debug` |
| Target version | Numeric candidate `CFBundleShortVersionString = X.Y.Z` |
| About display | `vX.Y.Z Debug (<build>)` |
| Update behavior | Disabled; never read or publish the production appcast |

Do not append `(Debug)` to `CFBundleShortVersionString`. The Debug label is presentation and
build-channel metadata. The `.debug` bundle identifier gives macOS a distinct runtime identity
for the local build. It does not establish a second product or release lineage, and it does not
by itself isolate every resource the code may address explicitly.

## One codebase, two runtime identities

Public and Debug are two build configurations of one repository and one codebase. They compile
the same candidate implementation into two bundles:

| | Public build | Local Debug build |
|---|---|---|
| Source and features | Same candidate code | Same candidate code |
| Build configuration | Release | Debug |
| Display name | `<App Name>` | `<App Name> Debug` |
| Bundle identifier | `<release-bundle-id>` | `<release-bundle-id>.debug` |
| Target version | `X.Y.Z` | `X.Y.Z` |
| Public distribution | Yes, after the tag gate | Never |

Do not maintain a copied Debug codebase. Put identity differences in Xcode build settings, the
SwiftPM assembly script, entitlements, or one small bundle-derived identity helper. Business and
feature logic stays shared so the code that passes Debug testing is the code that ships.

The distinct bundle identifier automatically separates the normal bundle-based application
identity, `UserDefaults.standard`, and TCC records. Anything addressed with a hardcoded or
explicit identifier must also be audited and either given a Debug namespace or disabled:

- explicit `UserDefaults` suites and Application Support, cache, database, and backup paths;
- login items, helper bundles, XPC services, Mach services, singleton locks, sockets, ports, and
  distributed-notification names;
- App Groups, iCloud containers, and Keychain access groups;
- Sparkle and any other production update mechanism;
- uninstall operations, which must never target the public bundle from Debug; and
- launch, quit, and cleanup scripts, which must match only the Debug bundle path or process.

Both bundles must be tested running at the same time. Starting, changing settings in, updating,
quitting, or uninstalling the Debug build must not change, terminate, update, or remove the
installed public release. Separate identity prevents collisions; this simultaneous-run test is
what confirms the app has no remaining shared-resource assumptions.

## What's New is part of the release

Every public release updates the in-app What's New content, including maintenance-only releases.
The heading continues to derive its version from `CFBundleShortVersionString`; the notes contain
no separately maintained current-version literal.

The public tag triggers the authoritative release gate. Before signing or notarization, it must:

1. Accept only an exact public `vX.Y.Z` tag.
2. Verify the tag version equals the built app's `CFBundleShortVersionString`.
3. Find the preceding public `vX.Y.Z` tag, excluding unrelated tag families.
4. Require the app's configured What's New source to have changed since that tag.
5. Reject an explicit current-version argument in `WhatsNewContent`.
6. Require meaningful notes or an explicit maintenance-only statement.
7. Run the app's normal automated tests and release checks.

The tag gate, not a pull request, is the release authority. A PR-time check may provide earlier
feedback but cannot replace the tag gate. A local preflight should run the same checks before
the tag is pushed so a simple omission is found while it is still cheap to fix.

If the pushed tag fails, it publishes no app release. Do not delete and move a release tag;
correct the problem, assign a fresh public version, and use a fresh tag.

## Marketing-site separation

The marketing site has no authority over whether an app ships. It owns its repository, build,
tests, deployment revision, changelog cache, and recovery process.

After a public app release succeeds, the release workflow sends a fire-and-forget webhook or
`repository_dispatch`. The site then reads published GitHub Releases and updates itself. The
notification must never make a successful app release fail, and a scheduled site-side refresh
provides a backstop for a missed event.

The site must ignore drafts and prereleases. Its automation may fail, retry, or deploy later
without affecting the signed app, GitHub Release, Homebrew distribution, or Sparkle updates.

Sparkle appcasts are update infrastructure, not marketing content. Each app should host its
production appcast in its own repository so an outage, permission problem, or rejected change in
the marketing-site repository cannot interfere with update delivery. Migrate an existing feed by
mirroring the old and new locations until installed versions have moved to the app-owned URL.

## Ownership summary

| Owner | Responsibilities |
|---|---|
| App repository | Source, tests, bundle version, What's New content, public tag |
| Shared release workflow | Tag gate, build, signing, notarization, publication |
| App-owned update feed | Production Sparkle appcast |
| Marketing-site repository | Fetch releases, generate changelog pages, test and deploy site |

## Acceptance criteria

The lifecycle is correctly implemented when:

- A developer can repeat the local Debug build-and-test loop without creating any tag or public
  artifact.
- Every local hands-on build visibly says `Debug` while its bundle version remains the numeric
  candidate intended for the next public release.
- The public release uses the exact candidate version that passed the Debug test loop, with the
  Debug label and `.debug` bundle identity removed.
- The installed public release and local Debug build can run simultaneously without sharing
  settings, terminating one another, or targeting one another's update or uninstall paths.
- A public tag cannot publish when the tag, bundle version, or What's New content is stale.
- The in-app version is derived from the bundle on every user-visible surface.
- Only a successful public release notifies the marketing site.
- A site failure cannot fail or delay the app release.
- Draft or prerelease GitHub entries never appear in the public changelog.
- Production appcasts are hosted independently from the marketing site.
