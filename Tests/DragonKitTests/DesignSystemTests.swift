import Testing
import SwiftUI
@testable import DragonKit

// MARK: - Compile-time coverage
//
// The load-bearing guarantee here is not a runtime assertion — it is that the call sites below
// still compile, and still compile *quietly*.
//
// `DragonForm` and `DragonSection` each carry a bare initializer alongside deprecated ice-2
// compatibility overloads whose parameters are all defaulted. Swift has to prefer the bare one;
// if it ever called the pair ambiguous instead, or picked the deprecated overload, that is a
// hard error and a deprecation warning respectively — either way this file tells you, on every
// build, instead of only on the day the change lands.
//
// These two structs are intentionally never instantiated. Type-checking them is the test.

/// The shape of the ~315 call sites across clipmenu-2, spectacle-2, yahoo-keykey-2, this kit and
/// the sample app that pass no layout arguments at all. Every one of them must stay warning-free.
@MainActor
private struct BareCallSites: View {
    var body: some View {
        DragonForm {
            DragonSection {
                Text(verbatim: "content only")
            }

            DragonSection("Title") {
                Text(verbatim: "titled content")
            }

            DragonSection {
                Text(verbatim: "header")
            } content: {
                Text(verbatim: "content")
            }

            DragonSection {
                Text(verbatim: "content")
            } footer: {
                Text(verbatim: "footer")
            }

            DragonSection {
                Text(verbatim: "header")
            } content: {
                Text(verbatim: "content")
            } footer: {
                Text(verbatim: "footer")
            }
        }
    }
}

/// The shape of ice-2's 30 call sites that do pass a layout argument. They are deprecated, not
/// removed: deleting the parameters would be a breaking change needing a major tag and a hand
/// bump in all four apps. This struct is itself marked deprecated because Swift suppresses
/// deprecation diagnostics inside a deprecated declaration — that is how it exercises the
/// compatibility overloads without adding warnings to a build that must stay clean.
@available(*, deprecated, message: "Exercises the deprecated ice-2 compatibility overloads.")
@MainActor
private struct ICE2CompatibilityCallSites: View {
    var body: some View {
        DragonForm(alignment: .leading, spacing: 20) {
            DragonSection(spacing: 4) {
                Text(verbatim: "content only")
            }

            DragonSection("Title", spacing: 4, options: .plain) {
                Text(verbatim: "titled content")
            }

            DragonSection(options: .plain) {
                Text(verbatim: "header")
            } content: {
                Text(verbatim: "content")
            }

            DragonSection(spacing: 4) {
                Text(verbatim: "content")
            } footer: {
                Text(verbatim: "footer")
            }

            DragonSection(spacing: 4, options: .isBordered) {
                Text(verbatim: "header")
            } content: {
                Text(verbatim: "content")
            } footer: {
                Text(verbatim: "footer")
            }
        }

        // The CGFloat-padding overload is a separate shape: `padding` has no default there, so
        // it is reachable only by passing it.
        DragonForm(padding: 0) {
            Text(verbatim: "content")
        }
    }
}

// MARK: - Runtime coverage

@Suite struct DragonFormTests {
    /// ice-2's `IceForm` call sites can still name these defaults explicitly, so the values are
    /// public API, not implementation detail — they are the `iceFormDefaultPadding` /
    /// `iceFormDefaultSpacing` numbers the port was checked against.
    @Test func defaultsKeepTheirICE2ParityValues() {
        #expect(EdgeInsets.dragonFormDefaultPadding == EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
        #expect(CGFloat.dragonFormDefaultSpacing == 10)
    }
}

@Suite struct DragonSectionTests {
    @Test func defaultSpacingKeepsItsICE2ParityValue() {
        #expect(CGFloat.dragonSectionDefaultSpacing == 11)
    }

    /// Two things at once, and this is the only test that actually *runs* an initializer.
    ///
    /// The generic parameters are the `where Header == EmptyView, Footer == EmptyView`
    /// constraints — dropping one from a bare initializer would silently hand ice-2 a different
    /// type. And the bare initializers delegate to each other while a same-arity deprecated
    /// overload is in scope, so if that delegation ever resolved to the wrong one this blows the
    /// stack rather than passing.
    @MainActor @Test func bareInitializersKeepTheirEmptyViewConstraints() {
        #expect(type(of: DragonSection { Text(verbatim: "c") }) == DragonSection<EmptyView, Text, EmptyView>.self)
        #expect(type(of: DragonSection("T") { Text(verbatim: "c") }) == DragonSection<Text, Text, EmptyView>.self)
        #expect(
            type(of: DragonSection { Text(verbatim: "c") } footer: { Text(verbatim: "f") })
                == DragonSection<EmptyView, Text, Text>.self
        )
        #expect(
            type(of: DragonSection { Text(verbatim: "h") } content: { Text(verbatim: "c") })
                == DragonSection<Text, Text, EmptyView>.self
        )
    }

    /// The deprecated overloads must actually *run*, not merely type-check.
    ///
    /// Everything else covering them is compile-time, and the specific hazard here is a runtime
    /// one that compiles perfectly: Swift suppresses deprecation diagnostics inside a deprecated
    /// declaration, so a deprecated initializer that delegated to *itself* instead of to its
    /// bare counterpart would recurse until the stack blew — silently, with no warning to hint
    /// at it. Constructing one of each shape is the only thing that can catch that. If this
    /// test ever crashes instead of failing, that recursion is why.
    ///
    /// Marked deprecated so exercising deprecated API doesn't dirty a build that must stay at
    /// zero warnings — the same idiom the compat call sites above use.
    @available(*, deprecated)
    @MainActor @Test func deprecatedInitializersStillTerminateAtRuntime() {
        #expect(type(of: DragonSection(spacing: 4, options: .plain) { Text(verbatim: "c") })
                == DragonSection<EmptyView, Text, EmptyView>.self)
        #expect(type(of: DragonSection("T", spacing: 4) { Text(verbatim: "c") })
                == DragonSection<Text, Text, EmptyView>.self)
        #expect(type(of: DragonSection(spacing: 4) { Text(verbatim: "c") } footer: { Text(verbatim: "f") })
                == DragonSection<EmptyView, Text, Text>.self)
        #expect(type(of: DragonSection(spacing: 4) { Text(verbatim: "h") } content: { Text(verbatim: "c") })
                == DragonSection<Text, Text, EmptyView>.self)
        #expect(type(of: DragonSection(spacing: 4) { Text(verbatim: "h") } content: { Text(verbatim: "c") }
                                                                          footer: { Text(verbatim: "f") })
                == DragonSection<Text, Text, Text>.self)
        #expect(type(of: DragonForm(padding: 8) { Text(verbatim: "c") }) == DragonForm<Text>.self)
        #expect(type(of: DragonForm(spacing: 8) { Text(verbatim: "c") }) == DragonForm<Text>.self)
    }

    /// `DragonSectionOptions` is a port of `IceSectionOptions`; the flags it packs into
    /// `.default` and `.plain` are what ice-2 call sites compare and combine against.
    @Test func optionsMatchTheICE2SetSemantics() {
        #expect(DragonSectionOptions.default.contains(.isBordered))
        #expect(DragonSectionOptions.default.contains(.hasDividers))
        #expect(DragonSectionOptions.plain.isEmpty)
        #expect(DragonSectionOptions.default == [.isBordered, .hasDividers])
    }
}
