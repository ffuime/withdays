import CoreGraphics
import Foundation

/// A line something snapped to, shown while dragging. In slide points.
struct SnapLine: Hashable {
    let vertical: Bool
    let position: Double
}

/// Where a moved or resized element settles: the slide's edges and middle, the guides (when shown),
/// and the edges and middles of the other elements.
struct Snapper {
    let xs: [Double]
    let ys: [Double]
    /// How close counts, in slide points.
    let threshold: Double

    init(slide: SlideContent, excluding id: UUID, guides: Bool, threshold: Double) {
        self.init(slide: slide, excluding: [id], guides: guides, threshold: threshold)
    }

    /// Several elements moved together don't snap to each other.
    init(slide: SlideContent, excluding ids: Set<UUID>, guides: Bool, threshold: Double) {
        var xs: [Double] = [0, 960, 1920]
        var ys: [Double] = [0, 540, 1080]
        if guides {
            xs += [480, 1440]
            ys += [270, 810]
        }
        for element in slide.elements where !ids.contains(element.id) {
            let bounds = Self.bounds(of: element)
            xs += [Double(bounds.minX), Double(bounds.midX), Double(bounds.maxX)]
            ys += [Double(bounds.minY), Double(bounds.midY), Double(bounds.maxY)]
        }
        self.xs = xs
        self.ys = ys
        self.threshold = threshold
    }

    /// The box around the element as it's drawn (turned elements take more room).
    static func bounds(of element: SlideElement) -> CGRect {
        if case .line(let line) = element.content { return line.bounds }
        let frame = element.frame.cg
        guard element.rotation.truncatingRemainder(dividingBy: 360) != 0 else { return frame }
        let angle = element.rotation * .pi / 180
        let width = abs(Double(frame.width) * cos(angle)) + abs(Double(frame.height) * sin(angle))
        let height = abs(Double(frame.width) * sin(angle)) + abs(Double(frame.height) * cos(angle))
        return CGRect(x: Double(frame.midX) - width / 2, y: Double(frame.midY) - height / 2, width: width, height: height)
    }

    /// The smallest shift that puts one of `values` on a target, and that target.
    func snap(_ values: [Double], vertical: Bool) -> (shift: Double, line: Double)? {
        var best: (shift: Double, line: Double)?
        for value in values {
            for target in vertical ? xs : ys {
                let shift = target - value
                guard abs(shift) <= threshold else { continue }
                if best == nil || abs(shift) < abs(best!.shift) { best = (shift, target) }
            }
        }
        return best
    }

    /// Moves the element so its edges or middle meet the nearest targets; returns the lines it met.
    func snapMove(_ element: inout SlideElement) -> [SnapLine] {
        let snapped = snapBounds(Self.bounds(of: element))
        if snapped.dx != 0 || snapped.dy != 0 { element.move(by: snapped.dx, snapped.dy) }
        return snapped.lines
    }

    /// The shift that puts a box's edges or middle on the nearest targets, and the lines it meets.
    func snapBounds(_ bounds: CGRect) -> (dx: Double, dy: Double, lines: [SnapLine]) {
        var lines: [SnapLine] = []
        var dx = 0.0, dy = 0.0
        if let x = snap([Double(bounds.minX), Double(bounds.midX), Double(bounds.maxX)], vertical: true) {
            dx = x.shift
            lines.append(SnapLine(vertical: true, position: x.line))
        }
        if let y = snap([Double(bounds.minY), Double(bounds.midY), Double(bounds.maxY)], vertical: false) {
            dy = y.shift
            lines.append(SnapLine(vertical: false, position: y.line))
        }
        return (dx, dy, lines)
    }

    /// One point (a line's end).
    func snapPoint(_ point: inout SlidePoint) -> [SnapLine] {
        var lines: [SnapLine] = []
        if let x = snap([point.x], vertical: true) {
            point.x += x.shift
            lines.append(SnapLine(vertical: true, position: x.line))
        }
        if let y = snap([point.y], vertical: false) {
            point.y += y.shift
            lines.append(SnapLine(vertical: false, position: y.line))
        }
        return lines
    }
}
