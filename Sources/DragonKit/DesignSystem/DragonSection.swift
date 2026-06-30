import SwiftUI

/// Compatibility options carried over from ice-2's `IceSectionOptions`. Grouping and
/// dividers are provided by the system grouped `Form`; these are accepted for source
/// compatibility with ice-2 call sites.
public struct DragonSectionOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let isBordered = DragonSectionOptions(rawValue: 1 << 0)
    public static let hasDividers = DragonSectionOptions(rawValue: 1 << 1)

    public static let plain: DragonSectionOptions = []
    public static let `default`: DragonSectionOptions = [.isBordered, .hasDividers]
}

/// A grouped settings section. Source-compatible port of ice-2's `IceSection`:
/// `spacing`/`options` are accepted for call-site compatibility.
public struct DragonSection<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer

    public init(
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    public init(
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init(spacing: spacing, options: options) { EmptyView() } content: { content() } footer: { footer() }
    }

    public init(
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(spacing: spacing, options: options) { header() } content: { content() } footer: { EmptyView() }
    }

    public init(
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init(spacing: spacing, options: options) { EmptyView() } content: { content() } footer: { EmptyView() }
    }

    public init(
        _ title: LocalizedStringKey,
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init(spacing: spacing, options: options) { Text(title) } content: { content() }
    }

    public var body: some View {
        Section {
            content
        } header: {
            header
        } footer: {
            footer
        }
    }
}

public extension CGFloat {
    /// Default spacing for a ``DragonSection``.
    static let dragonSectionDefaultSpacing: CGFloat = 11
}
