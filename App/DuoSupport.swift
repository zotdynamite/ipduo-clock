import IpduoClockCore
import SwiftUI

/// Two-pane layout for iPhone Duo.
///
/// When the app is built with the iOS 27.1 SDK (compilation condition `IPDUO_HAS_DUO_SDK`),
/// this uses `ArrangementView`, which splits or overlays around the fold on its own.
/// Earlier SDKs compile the size-class fallback only. `IPDUO_HAS_IOS26_SDK` enables
/// `backgroundExtensionEffect`, which shipped with iOS 26.
///
/// The Xcode project turns those conditions on from `Config/DuoSDK.xcconfig` when the
/// active SDK version matches. Add them by hand in Build Settings if it does not.
struct AdaptiveArrangement<Primary: View, Secondary: View>: View {
    enum Style {
        case split
        case overlay
    }

    var style: Style
    var axes: Axis.Set
    private let primary: Primary
    private let secondary: Secondary

    init(
        style: Style,
        axes: Axis.Set = [.horizontal, .vertical],
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.style = style
        self.axes = axes
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        #if IPDUO_HAS_DUO_SDK
        if #available(iOS 27.1, *) {
            DuoSystemArrangement(style: style, axes: axes, primary: primary, secondary: secondary)
        } else {
            DuoFallbackArrangement(style: style, axes: axes, primary: primary, secondary: secondary)
        }
        #else
        DuoFallbackArrangement(style: style, axes: axes, primary: primary, secondary: secondary)
        #endif
    }
}

struct DuoFallbackArrangement<Primary: View, Secondary: View>: View {
    var style: AdaptiveArrangement<Primary, Secondary>.Style
    var axes: Axis.Set
    var primary: Primary
    var secondary: Secondary

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass != .regular {
            compact
        } else {
            GeometryReader { proxy in
                let sideBySide = proxy.size.width >= proxy.size.height
                regular(sideBySide: sideBySide)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    @ViewBuilder
    private var compact: some View {
        switch style {
        case .split:
            primary
        case .overlay:
            ZStack(alignment: .bottom) {
                secondary
                primary
            }
        }
    }

    @ViewBuilder
    private func regular(sideBySide: Bool) -> some View {
        switch style {
        case .overlay:
            ZStack(alignment: .bottom) {
                secondary
                primary
            }
        case .split:
            if sideBySide && axes.contains(.horizontal) {
                HStack(spacing: 0) {
                    primary.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    secondary.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if axes.contains(.vertical) {
                VStack(spacing: 0) {
                    primary.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    secondary.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                primary
            }
        }
    }
}

#if IPDUO_HAS_DUO_SDK
@available(iOS 27.1, *)
struct DuoSystemArrangement<Primary: View, Secondary: View>: View {
    var style: AdaptiveArrangement<Primary, Secondary>.Style
    var axes: Axis.Set
    var primary: Primary
    var secondary: Secondary

    var body: some View {
        if style == .split {
            ArrangementView {
                primary
            } secondary: {
                secondary
            }
            .arrangementViewStyle(.split.axes(axes))
        } else {
            ArrangementView {
                primary
            } secondary: {
                secondary
            }
            .arrangementViewStyle(.overlay.axes(axes))
        }
    }
}
#endif

enum ReservedRegions {
    static func division(in proxy: GeometryProxy) -> LayoutRect? {
        #if IPDUO_HAS_DUO_SDK
        guard #available(iOS 27.1, *) else { return nil }
        guard let frame = proxy.reservedRegions(kind: .division).first?.frame else { return nil }
        return LayoutRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: frame.size.height)
        #else
        _ = proxy
        return nil
        #endif
    }

    static func occlusions(in proxy: GeometryProxy) -> [LayoutRect] {
        #if IPDUO_HAS_DUO_SDK
        guard #available(iOS 27.1, *) else { return [] }
        return proxy.reservedRegions(kind: .occlusion).map { region in
            let frame = region.frame
            return LayoutRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: frame.size.height)
        }
        #else
        _ = proxy
        return []
        #endif
    }
}

/// Reads the fold and camera regions when the SDK provides them, and keeps `content` in the clearer pane.
struct FoldSafeContainer<Content: View>: View {
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        GeometryReader { proxy in
            let frame = FoldLayout.contentFrame(
                containerWidth: proxy.size.width,
                containerHeight: proxy.size.height,
                division: ReservedRegions.division(in: proxy),
                occlusions: ReservedRegions.occlusions(in: proxy)
            )
            content(CGSize(width: frame.width, height: frame.height))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }
}

struct EvenColumnGrid<Item: Identifiable, Content: View>: View {
    var items: [Item]
    var minimumColumnWidth: CGFloat = 168
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        GeometryReader { proxy in
            let count = FoldLayout.evenColumnCount(
                containerWidth: proxy.size.width,
                minimumColumnWidth: minimumColumnWidth,
                division: ReservedRegions.division(in: proxy)
            )
            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: max(count, 1))
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { item in
                        content(item)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
    }
}

extension View {
    @ViewBuilder
    func duoBackgroundExtension() -> some View {
        #if IPDUO_HAS_IOS26_SDK
        if #available(iOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func duoSplitRatio(_ ratio: CGFloat) -> some View {
        #if IPDUO_HAS_DUO_SDK
        if #available(iOS 27.1, *) {
            self.splitArrangementLayoutRatio(ratio)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func duoPrefersTabBar() -> some View {
        #if IPDUO_HAS_DUO_SDK
        if #available(iOS 27.1, *) {
            self.toolbarVerticalCompressionBehavior(.prefersTabBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func duoPrefersToolbar() -> some View {
        #if IPDUO_HAS_DUO_SDK
        if #available(iOS 27.1, *) {
            self.toolbarVerticalCompressionBehavior(.prefersToolbarItems)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func duoPriorityHigh() -> some ToolbarContent {
        #if IPDUO_HAS_DUO_SDK
        if #available(iOS 27.0, *) {
            self.visibilityPriority(.high)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ToolbarContentBuilder
    func duoPriorityLow() -> some ToolbarContent {
        #if IPDUO_HAS_DUO_SDK
        if #available(iOS 27.0, *) {
            self.visibilityPriority(.low)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
