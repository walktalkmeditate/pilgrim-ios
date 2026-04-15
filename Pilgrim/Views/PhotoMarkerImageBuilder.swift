import UIKit

/// Builds circular marker images from reliquary photos for use as
/// Mapbox `PointAnnotation` icons. Takes a source `UIImage` (typically
/// the ~88pt Retina thumbnail from `PHImageManager`), crops it
/// aspect-fill into a square, clips to a circle, and strokes a stone
/// border so each pin on the route map actually looks like the photo
/// the pilgrim pinned — not a generic placeholder dot.
///
/// The caller is responsible for caching the result; this file builds
/// fresh images each call and doesn't track or persist anything.
enum PhotoMarkerImageBuilder {

    /// Default marker diameter in points. Matches the carousel
    /// thumbnail density — large enough to recognise the photo at
    /// normal zoom, small enough not to dominate the route.
    static let defaultDiameter: CGFloat = 44

    /// Default stroke width for the outer border.
    static let defaultBorderWidth: CGFloat = 2

    /// Builds a circular marker image from a source photo.
    ///
    /// - Parameters:
    ///   - sourceImage: The source photo (typically `PHImageManager`
    ///     output at ~88pt Retina target size).
    ///   - diameter: Outer diameter of the marker in points.
    ///   - borderWidth: Width of the stone border stroke.
    ///   - borderColor: Color of the border stroke.
    /// - Returns: A new `UIImage` sized `diameter × diameter` points
    ///   at the main-screen scale, with the source photo clipped to a
    ///   circle and stroked with the border. Returns a plain stone
    ///   placeholder if `sourceImage` has a degenerate size (0 in
    ///   either dimension).
    static func build(
        from sourceImage: UIImage,
        diameter: CGFloat = defaultDiameter,
        borderWidth: CGFloat = defaultBorderWidth,
        borderColor: UIColor = .stone
    ) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let insetRect = rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            let circlePath = UIBezierPath(ovalIn: insetRect)

            // Clip the drawing region to the circle so the photo's
            // square corners don't bleed past the border.
            ctx.cgContext.saveGState()
            circlePath.addClip()

            // Fill the clipped region with the border color first as
            // a safety net — if `sourceImage.draw(in:)` silently
            // no-ops (unusual but possible with a malformed CGImage),
            // the pin still has a visible circle instead of a
            // transparent hole.
            borderColor.setFill()
            circlePath.fill()

            if sourceImage.size.width > 0 && sourceImage.size.height > 0 {
                let imageRect = aspectFillRect(for: sourceImage.size, in: rect)
                sourceImage.draw(in: imageRect)
            }

            ctx.cgContext.restoreGState()

            // Stroke the outer border on top so it's always visible
            // regardless of the photo's edge contrast.
            borderColor.setStroke()
            circlePath.lineWidth = borderWidth
            circlePath.stroke()
        }
    }

    /// Builds a placeholder marker shown while the real photo is
    /// loading async from PhotoKit. Uses the same diameter + border
    /// as the real marker so the pin never shifts size when the
    /// photo swaps in.
    static func placeholder(
        diameter: CGFloat = defaultDiameter,
        borderWidth: CGFloat = defaultBorderWidth,
        borderColor: UIColor = .stone
    ) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let insetRect = rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            let path = UIBezierPath(ovalIn: insetRect)

            // Inner fill — a softer parchment tone so it reads as
            // "something is coming" rather than "this is the final pin".
            UIColor.parchmentSecondary.setFill()
            path.fill()

            borderColor.setStroke()
            path.lineWidth = borderWidth
            path.stroke()
        }
    }

    /// Aspect-fill scaling: the source image is scaled so its shorter
    /// dimension matches the target square, and the longer dimension
    /// is cropped by the clipping path.
    private static func aspectFillRect(for imageSize: CGSize, in target: CGRect) -> CGRect {
        let scale = max(target.width / imageSize.width, target.height / imageSize.height)
        let scaled = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let origin = CGPoint(
            x: target.midX - scaled.width / 2,
            y: target.midY - scaled.height / 2
        )
        return CGRect(origin: origin, size: scaled)
    }
}
