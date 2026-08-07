import SwiftUI

/// Compatibility options carried over from ice-2's `IceSectionOptions`. Grouping and
/// dividers are provided by the system grouped `Form`; these are accepted for source
/// compatibility with ice-2 call sites and have no effect.
public struct DragonSectionOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let isBordered = DragonSectionOptions(rawValue: 1 << 0)
    public static let hasDividers = DragonSectionOptions(rawValue: 1 << 1)

    public static let plain: DragonSectionOptions = []
    public static let `default`: DragonSectionOptions = [.isBordered, .hasDividers]
}

/// A grouped settings section. Source-compatible port of ice-2's `IceSection`.
///
/// Same story as ``DragonForm``: ice-2's `IceSection` drew its own box, so it took `spacing`
/// and `options`. The port hands both to the system grouped `Form` and ignores the arguments,
/// so a call site writing `spacing: 20` or `options: .plain` got silence.
///
/// The parameters stay — removing them would break ice-2's call sites and force a major tag
/// and a hand bump in all four apps — but only on deprecated overloads. Every shape below
/// therefore exists twice: a bare one that Swift prefers (it needs no defaulted arguments), and
/// a deprecated compatibility one that only wins when a call site actually passes `spacing:` or
/// `options:`. That keeps the ~315 call sites that pass nothing completely silent while the ones
/// that do pass something finally hear about it.
public struct DragonSection<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer

    public init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init { EmptyView() } content: { content() } footer: { footer() }
    }

    public init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init { header() } content: { content() } footer: { EmptyView() }
    }

    public init(
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init { EmptyView() } content: { content() } footer: { EmptyView() }
    }

    public init(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init { Text(title) } content: { content() }
    }

    // MARK: - Deprecated ice-2 compatibility overloads
    //
    // These delegate among themselves (always passing `spacing:`/`options:` on), never to the
    // bare initializers above, so the label sets keep the resolution unambiguous in both
    // directions. Deprecation diagnostics are suppressed inside a deprecated declaration, which
    // would otherwise hide a mis-resolution here.

    @available(
        *, deprecated,
        message: """
            spacing: and options: have never had any effect — delete the argument; \
            DragonSection's layout comes from the grouped Form.
            """
    )
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

    @available(
        *, deprecated,
        message: """
            spacing: and options: have never had any effect — delete the argument; \
            DragonSection's layout comes from the grouped Form.
            """
    )
    public init(
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init(spacing: spacing, options: options) { EmptyView() } content: { content() } footer: { footer() }
    }

    @available(
        *, deprecated,
        message: """
            spacing: and options: have never had any effect — delete the argument; \
            DragonSection's layout comes from the grouped Form.
            """
    )
    public init(
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(spacing: spacing, options: options) { header() } content: { content() } footer: { EmptyView() }
    }

    @available(
        *, deprecated,
        message: """
            spacing: and options: have never had any effect — delete the argument; \
            DragonSection's layout comes from the grouped Form.
            """
    )
    public init(
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init(spacing: spacing, options: options) { EmptyView() } content: { content() } footer: { EmptyView() }
    }

    @available(
        *, deprecated,
        message: """
            spacing: and options: have never had any effect — delete the argument; \
            DragonSection's layout comes from the grouped Form.
            """
    )
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
