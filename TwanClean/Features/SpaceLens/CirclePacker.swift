import CoreGraphics
import Foundation

/// Lays out circles whose areas follow the given sizes, without overlap, and
/// scales the cluster to fit a canvas. The result depends only on the input,
/// so the same folder always looks the same.
enum CirclePacker {
    /// The smallest circle, relative to the largest, so tiny items stay
    /// visible and clickable.
    static let minimumRadiusRatio: CGFloat = 0.12
    /// Space between circles, relative to a largest radius of 100.
    static let gap: CGFloat = 3

    /// Frames in the same order as `sizes`.
    static func pack(_ sizes: [Int64], in canvas: CGSize, padding: CGFloat = 8) -> [CGRect] {
        guard !sizes.isEmpty, canvas.width > 2 * padding, canvas.height > 2 * padding else { return [] }
        let largest = CGFloat(max(sizes.max() ?? 1, 1))
        let radii = sizes.map { size -> CGFloat in
            max((CGFloat(max(size, 0)) / largest).squareRoot(), minimumRadiusRatio) * 100
        }

        var centers: [CGPoint] = []
        let pitch = (radii.first ?? 100) / 40
        for (index, radius) in radii.enumerated() {
            guard index > 0 else {
                centers.append(.zero)
                continue
            }
            // Walk an outward spiral until the circle touches nothing.
            var angle: CGFloat = 0
            while true {
                let distance = pitch * angle
                let candidate = CGPoint(x: distance * cos(angle), y: distance * sin(angle))
                let overlaps = centers.indices.contains { other in
                    hypot(candidate.x - centers[other].x, candidate.y - centers[other].y)
                        < radius + radii[other] + gap
                }
                if !overlaps {
                    centers.append(candidate)
                    break
                }
                angle += 0.35
            }
        }

        // Fit the cluster's bounding box into the canvas.
        let minX = zip(centers, radii).map { $0.x - $1 }.min()!
        let maxX = zip(centers, radii).map { $0.x + $1 }.max()!
        let minY = zip(centers, radii).map { $0.y - $1 }.min()!
        let maxY = zip(centers, radii).map { $0.y + $1 }.max()!
        let available = CGSize(width: canvas.width - 2 * padding, height: canvas.height - 2 * padding)
        let scale = min(available.width / (maxX - minX), available.height / (maxY - minY))
        let offset = CGPoint(x: (canvas.width - (maxX - minX) * scale) / 2 - minX * scale,
                             y: (canvas.height - (maxY - minY) * scale) / 2 - minY * scale)
        return zip(centers, radii).map { center, radius in
            CGRect(x: center.x * scale + offset.x - radius * scale,
                   y: center.y * scale + offset.y - radius * scale,
                   width: 2 * radius * scale, height: 2 * radius * scale)
        }
    }
}
