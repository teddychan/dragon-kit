# Changelog

DragonKit is the shared toolkit behind the five Dragon apps — ClipMenu 2, Ice 2, Spectacle 2,
Yahoo! KeyKey 2 and Dragon Sample App. It isn't an app you install. It's the common parts those
five apps are built from: their Settings window, their About screen, their menu, their
translations. Changing something here changes it in all five at once.

Each entry says plainly what changed and whether anyone using the apps would notice.

Versions follow `major.minor.patch`. The middle number going up means things were added and
nothing that already worked was taken away.

---

## 4.1.0 — 2026-08-16

**Would anyone using the apps notice? Almost nothing.** No screen was redesigned and no feature
was added or removed. This release is mostly about the automatic checks that keep the five apps
consistent with each other — catching mistakes before they reach anyone, rather than changing what
people see. The one visible thing is that every app's About screen will now say
`Built with · DragonKit v4.1.0`.

### New automatic checks

These run by themselves whenever anyone proposes a change to one of the five apps, and block the
change if it fails.

- **The website link in About must point at that app's own page.** Every app's About screen has a
  "Website" row. Nothing used to verify it went to the right place — and a wrong link still opens
  a real page in a browser, so nobody would spot it. It's now checked against the app's own
  support link, which has to agree.
- **An app's language menu can only offer languages it has actually been translated into.** One
  app was offering five languages it had no translations for. Picking one of them translated a few
  shared screens and left everything else in English. That can't happen again.
- **The order of the Settings sidebar has to be written the same way everywhere.** That order is
  described in eight different documents. Two of them had drifted into disagreeing. They're now
  compared automatically, so a change to one that misses the others is caught immediately.

### Fixed

- **A website link on a completely different site used to pass the check.** Only the last part of
  the address was compared, so a link to the right *page name* on the wrong *website* looked
  correct. Both halves are compared now.
- **Disabled code used to count as working code.** Several checks read the app's source as plain
  text, so a line someone had commented out — switched off, but left in place — still counted as
  though the app were doing the right thing. They read the actual working code now.
- **Some checks quietly passed apps by having nothing to look at.** If an app's configuration file
  left out a setting, the check that depended on it switched itself off in silence and reported
  success. A missing setting is now a failure, because a check that goes quiet is worse than no
  check at all.
- **A version check could read the wrong version number.** In one app's project file it was
  picking up a different component's version entirely and comparing that, reporting everything was
  up to date when it wasn't.
- **"Debug" appeared inside example version numbers** in the release documentation, in the two
  tables most likely to be copied — while the same document says twice that it must never go
  there. A debug build is identified by its name and a separate marker, never by its version
  number.

### Documentation

- **The rules and the reasons behind them are now separate.** The rules document had grown to the
  point where the story behind each rule sat between a reader and the rule itself. Every rule kept
  its reasoning — it just moved to its own document, linked both ways. Nothing was discarded.
- **Every shared fact now has one owner.** Facts repeated across up to eight documents had quietly
  started disagreeing. Each is now stated once, and the others point at it.
- **The original 2026 build plan is now a decision record.** It was 1,412 lines of step-by-step
  build instructions for software that has since been built. The decisions it made are kept; the
  instructions are in version history.

### For developers

- Added `DragonAbout.isDragonAppSite(_:)`.
- `AboutContent.websiteMatchesSupportRepo` now compares hosts on the label boundary, so `www.` is
  the same site and `notgithub.com` is not.
- New rules §R13 and §R15; the About-copyright rule renumbered to §R14.
- No public symbol was removed, renamed, or had its signature changed. Bumping the pin from 4.0.0
  requires no source changes in any app.

---

Releases before 4.1.0 predate this file. See the
[tag list](https://github.com/teddychan/dragon-kit/tags) and each pull request for the detail.
