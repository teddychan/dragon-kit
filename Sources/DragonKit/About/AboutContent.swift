import AppKit

/// One assembled row in the About pane's links section. Built by ``AboutContent``, never by an
/// app — the title and symbol are kit-owned so the row reads identically in every Dragon app.
public struct AboutLinkRow: Identifiable, Sendable, Equatable {
    public var id: String { systemImage + title }
    public let title: String
    public let detail: String
    public let systemImage: String
    public let url: URL
}

/// One assembled row in the About pane's Credits section.
public struct AboutCreditRow: Sendable, Equatable {
    public let label: String
    public let value: String
}

/// The upstream project a Dragon app reimplements, rendered as `<name> by <author>`.
///
/// A struct rather than a tuple so it is `Equatable` for the canon tests. The "by" is kit-owned
/// too: ice-2 wrote "Original Ice → Jordan Baird", spectacle-2 wrote "Based on → Spectacle by
/// Eric Czarny", and clipmenu-2 a third way. One label, one joining word, one shape.
public struct OriginalWork: Sendable, Equatable {
    public let name: String
    public let author: String

    public init(name: String, author: String) {
        self.name = name
        self.author = author
    }
}

/// A third-party thing an app bundles, and its licence — listed at the end of Credits.
///
/// The only genuinely app-specific rows in the pane, and therefore the one place left where two
/// apps could still look different. They did, within a day of 3.0.0 shipping: clipmenu-2 wrote
/// `Sparkle → MIT` while the sample app wrote `Update framework → Sparkle (MIT)`. Same type, two
/// shapes, exactly the drift the fixed slots removed everywhere else.
///
/// **The canon is name → licence**: the thing's own name as its authors spell it, then its SPDX
/// licence. `Sparkle → MIT`, `OpenCC → Apache-2.0`. It reads as a standard acknowledgements list
/// and scales to ice-2's six bundled libraries, where inventing a role label for each ("Slider
/// control", "Accessibility bridge") would be one more thing to get inconsistent.
///
/// The field *names* carry that rule, which is why they changed: nobody writes a role into
/// something called `name` or an origin into something called `license` by accident. The old
/// `component`/`source` spelling stays as deprecated aliases rather than being removed — deleting
/// public members would force a major tag and a hand bump in all four apps, the same trade
/// ``DragonSection`` records for its deprecated overloads.
public struct Attribution: Sendable, Equatable {
    /// The library or data set's own name — `Sparkle`, `OpenCC`, `ibus-table-chinese`.
    public let name: String
    /// Its licence, SPDX-style — `MIT`, `Apache-2.0`, `GPL-3.0`.
    public let license: String

    public init(name: String, license: String) {
        self.name = name
        self.license = license
    }

    @available(*, deprecated, message: "Attributions are name → licence: Attribution(name: \"Sparkle\", license: \"MIT\"). A role label such as \"Update framework\" is not a name.")
    public init(component: String, source: String) {
        self.init(name: component, license: source)
    }

    @available(*, deprecated, renamed: "name")
    public var component: String { name }

    @available(*, deprecated, renamed: "license")
    public var source: String { license }
}

/// App-supplied content for the shared About pane.
///
/// **Fixed slots, deliberately.** This type used to take `links: [AboutLink]` and
/// `credits: [(label: String, value: String)]` — free-form arrays in which the app chose every
/// title, SF Symbol, label and row count. Five apps then hand-wrote five `AboutConfig.swift`
/// files and shipped five visibly different About panes: "Support on GitHub" beside "Report an
/// issue on GitHub" beside "Source", three different symbols for that one row, a "License" row
/// missing in one app, and a copyright field holding `倉頡／簡易 輸入法` instead of a copyright.
///
/// The kit owned the frame and nothing inside it, so the arrays are gone. An app now supplies
/// URLs and proper nouns; ``linkRows`` and ``creditRows`` assemble every title, symbol and
/// ordering here. Adding, renaming, re-iconing or reordering a row is a compile error rather
/// than something spotted in a screenshot months later.
public struct AboutContent {
    // MARK: Header

    public let appName: String
    /// Always ``DragonAbout/versionString(bundle:)``. spectacle-2 hand-rolled
    /// `"\(short) (\(build))"` and lost both the `v` prefix and the build timestamp.
    public let versionString: String
    /// Always ``DragonAbout/copyright(original:years:holder:)``.
    public let copyright: String
    public let appIcon: NSImage?

    // MARK: Links — fixed slots

    /// The app's canonical marketing page, `https://www.dragonapp.com/{app-name}-{major}/`.
    ///
    /// The site's canonical URLs are all repo-named; `/clipmenu/` and `/keykey/` are `<meta
    /// refresh>` stubs whose `rel=canonical` points at `/clipmenu-2/` and `/yahoo-keykey-2/`.
    /// clipmenu-2 and yahoo-keykey-2 linked those stubs and spectacle-2 linked the bare hub —
    /// three of five apps wrong — so ``websiteMatchesSupportRepo`` checks this against
    /// ``supportURL``'s repo name.
    public let websiteURL: URL
    /// The GitHub issues page. ice-2, clipmenu-2 and yahoo-keykey-2 pointed here; spectacle-2
    /// and the sample app pointed at the repo root and titled the row "Source" instead.
    public let supportURL: URL
    /// The upstream project's repository, when the app reimplements one.
    public let originalProjectURL: URL?
    /// Third-party licence notices, hosted at `dragonapp.com/{app}/licenses`.
    ///
    /// Replaces the bundled Acknowledgements document ice-2 shipped: a hand-maintained RTF/PDF
    /// carrying full MIT text for six libraries. Hosting them on the site rather than in the
    /// bundle is a weaker reading of MIT's "included in all copies" and was chosen knowingly —
    /// see the design spec.
    public let licensesURL: URL?

    // MARK: Credits — fixed slots

    public let createdBy: String
    public let originalWork: OriginalWork?
    /// The app's *own* licence (`MIT`, `GPL-3.0`) — not the third-party notices behind
    /// ``licensesURL``. Two licence-shaped rows that mean different things; don't merge them.
    public let license: String
    public let attributions: [Attribution]

    public init(
        appName: String,
        versionString: String,
        copyright: String,
        websiteURL: URL,
        supportURL: URL,
        license: String,
        appIcon: NSImage? = NSImage(named: NSImage.applicationIconName),
        originalProjectURL: URL? = nil,
        licensesURL: URL? = nil,
        createdBy: String = "Teddy Chan",
        originalWork: OriginalWork? = nil,
        attributions: [Attribution] = []
    ) {
        self.appName = appName
        self.versionString = versionString
        self.copyright = copyright
        self.websiteURL = websiteURL
        self.supportURL = supportURL
        self.license = license
        self.appIcon = appIcon
        self.originalProjectURL = originalProjectURL
        self.licensesURL = licensesURL
        self.createdBy = createdBy
        self.originalWork = originalWork
        self.attributions = attributions
    }

    // MARK: Assembled rows

    /// The links section, in canonical order. Optional slots collapse without reordering the
    /// rest.
    ///
    /// Detail text is *derived* from the URL, never typed: yahoo-keykey-2 wrote
    /// `www.dragonapp.com/keykey` where every other app omitted the `www.`, and a typed string
    /// can disagree with the URL it sits beside. ``AboutLinkDetail`` is the single formatter.
    @MainActor
    public var linkRows: [AboutLinkRow] {
        var rows = [
            AboutLinkRow(
                title: L("DragonKit.about.website"),
                detail: AboutLinkDetail.detail(for: websiteURL),
                systemImage: "globe",
                url: websiteURL
            ),
            AboutLinkRow(
                title: L("DragonKit.about.support"),
                detail: AboutLinkDetail.detail(for: supportURL),
                systemImage: "lifepreserver",
                url: supportURL
            ),
        ]
        if let originalProjectURL {
            rows.append(AboutLinkRow(
                title: L("DragonKit.about.original"),
                detail: AboutLinkDetail.detail(for: originalProjectURL),
                systemImage: "heart",
                url: originalProjectURL
            ))
        }
        if let licensesURL {
            rows.append(AboutLinkRow(
                title: L("DragonKit.about.licenses"),
                detail: AboutLinkDetail.detail(for: licensesURL),
                systemImage: "doc.text",
                url: licensesURL
            ))
        }
        return rows
    }

    /// The Credits section, in canonical order: Created by → Based on → Built with → License →
    /// attributions.
    ///
    /// "Built with · DragonKit vX.Y.Z" has no corresponding stored property on purpose. It is
    /// the one row that says which kit a binary actually compiled against, so an app can neither
    /// omit it, move it, nor state a version of its own.
    @MainActor
    public var creditRows: [AboutCreditRow] {
        var rows = [AboutCreditRow(label: L("DragonKit.about.createdBy"), value: createdBy)]
        if let originalWork {
            rows.append(AboutCreditRow(
                label: L("DragonKit.about.basedOn"),
                value: "\(originalWork.name) by \(originalWork.author)"
            ))
        }
        rows.append(AboutCreditRow(
            label: L("DragonKit.about.builtWith"),
            value: "DragonKit \(DragonVersion.display(DragonKitVersion.current))"
        ))
        rows.append(AboutCreditRow(label: L("DragonKit.about.license"), value: license))
        rows.append(contentsOf: attributions.map {
            AboutCreditRow(label: $0.name, value: $0.license)
        })
        return rows
    }

    /// Whether ``websiteURL`` addresses the canonical page for ``supportURL``'s repository.
    ///
    /// The site convention is `{app-name}-{major}`, which is also the GitHub repo name for every
    /// Dragon app — so the two rows check each other with no table to maintain. The Dragon
    /// Sample App is the sanctioned exception: it has no marketing page and points at the hub.
    public var websiteMatchesSupportRepo: Bool {
        guard let repo = AboutLinkDetail.repository(of: supportURL) else { return false }
        let path = websiteURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path == repo
    }
}

/// Formats a link's trailing detail text from its URL, so no app can type one that disagrees
/// with where the row actually goes.
public enum AboutLinkDetail {
    /// `https://github.com/teddychan/ice-2/issues` → `teddychan/ice-2`;
    /// `https://www.dragonapp.com/ice-2/` → `dragonapp.com/ice-2`.
    public static func detail(for url: URL) -> String {
        if let repo = repository(of: url), let owner = owner(of: url) {
            return "\(owner)/\(repo)"
        }
        let host = (url.host ?? "").replacingOccurrences(
            of: "^www\\.", with: "", options: .regularExpression
        )
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? host : "\(host)/\(path)"
    }

    /// The repository name in a `github.com/owner/repo/...` URL.
    public static func repository(of url: URL) -> String? { gitHubComponents(of: url)?.repo }

    /// The owner in a `github.com/owner/repo/...` URL.
    public static func owner(of url: URL) -> String? { gitHubComponents(of: url)?.owner }

    private static func gitHubComponents(of url: URL) -> (owner: String, repo: String)? {
        guard url.host?.hasSuffix("github.com") == true else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }
}
