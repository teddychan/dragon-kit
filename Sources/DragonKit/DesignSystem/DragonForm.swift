import SwiftUI

/// A settings form on the system's grouped `Form`. Source-compatible port of ice-2's
/// `IceForm`: layout params are accepted for call-site compatibility; layout is driven
/// by the grouped `Form`.
public struct DragonForm<Content: View>: View {
    private let content: Content

    public init(
        alignment: HorizontalAlignment = .center,
        padding: EdgeInsets = .dragonFormDefaultPadding,
        spacing: CGFloat = .dragonFormDefaultSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

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
