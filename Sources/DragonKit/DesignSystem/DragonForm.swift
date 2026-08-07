import SwiftUI

/// A settings form on the system's grouped `Form`. Source-compatible port of ice-2's `IceForm`.
///
/// ice-2's `IceForm` laid itself out by hand, so it took `alignment`/`padding`/`spacing`. The
/// port draws on the system grouped `Form`, which owns all three — so the port accepted those
/// parameters and then dropped them on the floor. A call site writing `spacing: 20` got silence:
/// no effect, no diagnostic, nothing in the docs saying so.
///
/// Keeping the parameters is still right — deleting them would break ice-2's 30 call sites that
/// pass one, and that is a major-version, bump-four-apps-by-hand change. So they stay, on
/// deprecated overloads: passing one now says at compile time that it does nothing, while the
/// ~315 call sites across the four apps that pass nothing bind to the barer initializer below
/// and keep compiling in total silence.
public struct DragonForm<Content: View>: View {
    private let content: Content

    /// The initializer every call site should use. It is deliberately barer than the
    /// compatibility overloads: Swift prefers an initializer that needs no defaulted arguments,
    /// so a bare `DragonForm { … }` binds here and never trips their deprecation.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @available(
        *, deprecated,
        message: """
            alignment:, padding: and spacing: have never had any effect — delete the argument; \
            DragonForm's layout comes from the grouped Form.
            """
    )
    public init(
        alignment: HorizontalAlignment = .center,
        padding: EdgeInsets = .dragonFormDefaultPadding,
        spacing: CGFloat = .dragonFormDefaultSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    @available(
        *, deprecated,
        message: """
            alignment:, padding: and spacing: have never had any effect — delete the argument; \
            DragonForm's layout comes from the grouped Form.
            """
    )
    public init(
        alignment: HorizontalAlignment = .center,
        padding: CGFloat,
        spacing: CGFloat = .dragonFormDefaultSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    public var body: some View {
        Form { content }
            .formStyle(.grouped)
            .focusSection()
            .accessibilityElement(children: .contain)
    }
}

public extension EdgeInsets {
    /// Default padding for a ``DragonForm`` (port of ice-2's `iceFormDefaultPadding`).
    static let dragonFormDefaultPadding = EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20)
}

public extension CGFloat {
    /// Default spacing for a ``DragonForm``.
    static let dragonFormDefaultSpacing: CGFloat = 10
}
