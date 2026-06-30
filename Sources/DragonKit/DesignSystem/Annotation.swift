import SwiftUI

/// Displays content as an annotation below a parent view. Port of ice-2's `AnnotationView`.
public struct DragonAnnotationView<Parent: View, Content: View, FG: ShapeStyle>: View {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat
    private let font: Font?
    private let foregroundStyle: FG
    private let parent: Parent
    private let content: Content

    public init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .dragonAnnotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: FG = .secondary,
        @ViewBuilder parent: () -> Parent,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.font = font
        self.foregroundStyle = foregroundStyle
        self.parent = parent()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            parent
            content
                .font(font)
                .foregroundStyle(foregroundStyle)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .fixedSize(horizontal: false, vertical: true)
    }
}

public extension View {
    /// Adds a view as an annotation below this view. Port of ice-2's `.annotation`.
    func dragonAnnotation<Content: View, FG: ShapeStyle>(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .dragonAnnotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: FG = .secondary,
        @ViewBuilder content: () -> Content
    ) -> some View {
        DragonAnnotationView(
            alignment: alignment, spacing: spacing, font: font, foregroundStyle: foregroundStyle
        ) { self } content: { content() }
    }

    /// Adds text as an annotation below this view. Port of ice-2's `.annotation(_:)`.
    func dragonAnnotation<FG: ShapeStyle>(
        _ titleKey: LocalizedStringKey,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .dragonAnnotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: FG = .secondary
    ) -> some View {
        dragonAnnotation(
            alignment: alignment, spacing: spacing, font: font, foregroundStyle: foregroundStyle
        ) { Text(titleKey) }
    }
}

public extension CGFloat {
    /// Default spacing for a ``DragonAnnotationView`` (ice-2 parity).
    static let dragonAnnotationDefaultSpacing: CGFloat = 2
}
