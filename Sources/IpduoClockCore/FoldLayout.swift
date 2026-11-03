import Foundation

/// A rectangle in the view's own coordinates. `x` grows trailing, `y` grows downward.
public struct LayoutRect: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = LayoutRect(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func intersects(_ other: LayoutRect) -> Bool {
        maxX > other.minX && minX < other.maxX && maxY > other.minY && minY < other.maxY
    }

    public func intersection(_ other: LayoutRect) -> LayoutRect {
        let nx = max(minX, other.minX)
        let ny = max(minY, other.minY)
        let nw = min(maxX, other.maxX) - nx
        let nh = min(maxY, other.maxY) - ny
        guard nw > 0, nh > 0 else { return .zero }
        return LayoutRect(x: nx, y: ny, width: nw, height: nh)
    }
}

/// Pure geometry for keeping content off a fold and choosing an even column count.
/// Division and occlusion rectangles match SwiftUI `ReservedRegion` frames:
/// occlusion frames already include their margins.
public enum FoldLayout {
    public static func contentFrame(
        containerWidth: Double,
        containerHeight: Double,
        division: LayoutRect?,
        occlusions: [LayoutRect] = []
    ) -> LayoutRect {
        let full = LayoutRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
        guard containerWidth > 1, containerHeight > 1 else { return full }
        let chosen = choosePane(panes(in: full, division: division))
        let cleared = inset(chosen, avoiding: occlusions)
        if cleared.width < 24 || cleared.height < 24 { return chosen }
        return cleared
    }

    public static func panes(in container: LayoutRect, division: LayoutRect?) -> [LayoutRect] {
        guard let division, division.width > 0.5, division.height > 0.5, container.intersects(division) else {
            return [container]
        }
        if division.height > division.width {
            let leading = LayoutRect(
                x: container.minX,
                y: container.minY,
                width: max(0, division.minX - container.minX),
                height: container.height
            )
            let trailing = LayoutRect(
                x: division.maxX,
                y: container.minY,
                width: max(0, container.maxX - division.maxX),
                height: container.height
            )
            return [leading, trailing].filter { $0.width > 1 && $0.height > 1 }
        }
        let top = LayoutRect(
            x: container.minX,
            y: container.minY,
            width: container.width,
            height: max(0, division.minY - container.minY)
        )
        let bottom = LayoutRect(
            x: container.minX,
            y: division.maxY,
            width: container.width,
            height: max(0, container.maxY - division.maxY)
        )
        return [top, bottom].filter { $0.width > 1 && $0.height > 1 }
    }

    /// Even column counts when the grid is wide enough to use them.
    /// A vertical fold always asks for two columns so items fall on either side of the hinge.
    /// A narrow container that cannot fit two columns stays at one.
    public static func evenColumnCount(
        containerWidth: Double,
        minimumColumnWidth: Double,
        division: LayoutRect? = nil
    ) -> Int {
        if let division, division.height > division.width {
            return 2
        }
        let slot = max(minimumColumnWidth, 1)
        let fit = max(1, Int(floor(containerWidth / slot)))
        if fit <= 1 { return 1 }
        return fit - (fit % 2)
    }

    private static func choosePane(_ panes: [LayoutRect]) -> LayoutRect {
        guard var best = panes.first else { return .zero }
        for pane in panes.dropFirst() where area(pane) > area(best) + 0.5 {
            best = pane
        }
        return best
    }

    private static func area(_ rect: LayoutRect) -> Double {
        max(0, rect.width) * max(0, rect.height)
    }

    private static func inset(_ pane: LayoutRect, avoiding occlusions: [LayoutRect]) -> LayoutRect {
        var rect = pane
        for occlusion in occlusions where rect.intersects(occlusion) {
            let overlap = occlusion.intersection(rect)
            guard overlap.width > 0, overlap.height > 0 else { continue }
            let fromTop = overlap.midY - rect.minY
            let fromBottom = rect.maxY - overlap.midY
            let fromLeading = overlap.midX - rect.minX
            let fromTrailing = rect.maxX - overlap.midX
            let edge = min(fromTop, fromBottom, fromLeading, fromTrailing)
            var candidate = rect
            if edge == fromTop {
                candidate.y = overlap.maxY
                candidate.height = rect.maxY - candidate.y
            } else if edge == fromBottom {
                candidate.height = overlap.minY - rect.minY
            } else if edge == fromLeading {
                candidate.x = overlap.maxX
                candidate.width = rect.maxX - candidate.x
            } else {
                candidate.width = overlap.minX - rect.minX
            }
            if candidate.width > rect.width * 0.45 && candidate.height > rect.height * 0.45 {
                rect = candidate
            }
        }
        return rect
    }
}
