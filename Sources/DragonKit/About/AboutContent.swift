import AppKit

/// A single labeled link shown in the About pane.
public struct AboutLink: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let detail: String
    public let systemImage: String
    public let url: URL

    public init(title: String, detail: String, systemImage: String, url: URL) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.url = url
    }
}

/// App-supplied content for the shared About pane.
public struct AboutContent {
    public let appName: String
    public let versionString: String
    public let copyright: String
    public let appIcon: NSImage?
    public let links: [AboutLink]
    public let credits: [(label: String, value: String)]
    public let acknowledgementsURL: URL?

    public init(
        appName: String,
        versionString: String,
        copyright: String,
        appIcon: NSImage? = NSImage(named: NSImage.applicationIconName),
        links: [AboutLink] = [],
        credits: [(label: String, value: String)] = [],
        acknowledgementsURL: URL? = nil
    ) {
        self.appName = appName
        self.versionString = versionString
        self.copyright = copyright
        self.appIcon = appIcon
        self.links = links
        self.credits = credits
        self.acknowledgementsURL = acknowledgementsURL
    }
}
