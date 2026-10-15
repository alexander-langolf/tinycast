import AppKit
import ImageIO

enum NotchBackdropReader {
    /// The wallpaper colour behind the notch bar's top band; reading the file needs no permission.
    static func sample(screen: NSScreen, panel: CGRect, band: CGFloat) async -> NotchBackdropColor? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let frame = screen.frame
        return await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateThumbnailAtIndex(
                    source, 0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 512
                    ] as CFDictionary)
            else { return nil }
            let width = image.width
            let height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            let screenAspect = frame.width / frame.height
            let imageAspect = Double(width) / Double(height)
            let across = NotchBackdrop.imageRange(
                screen: ((panel.minX - frame.minX) / frame.width)...((panel.maxX - frame.minX) / frame.width),
                screenAspect: screenAspect, imageAspect: imageAspect, horizontal: true)
            let down = NotchBackdrop.imageRange(
                screen: 0...Double(band / frame.height), screenAspect: screenAspect, imageAspect: imageAspect,
                horizontal: false)
            return NotchBackdrop.average(rgba: pixels, width: width, height: height, x: across, y: down)
        }.value
    }
}
