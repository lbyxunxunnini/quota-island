import Foundation

enum LayoutPlanner {
    static func boardRows<Element>(_ items: [Element]) -> [[Element]] {
        stride(from: 0, to: items.count, by: 2).map {
            Array(items[$0..<min($0 + 2, items.count)])
        }
    }

    static func compactSides<Element>(_ items: [Element]) -> (left: [Element], right: [Element]) {
        let visible = Array(items.prefix(3))
        let leftCount = min(2, (visible.count + 1) / 2)
        return (Array(visible.prefix(leftCount)), Array(visible.dropFirst(leftCount)))
    }
}
