import Accelerate
import CoreGraphics
import libass
import QuartzCore

/// Pipeline that processed an `ASS_Image` into a ``ProcessedImage``
/// by combining all images using `vImage.PixelBuffer`.
@available(iOS 16.0, tvOS 16.0, visionOS 1.0, macOS 13.0, macCatalyst 16.0, *)
public final class AccelerateImagePipeline {
    public static func process(images: [ASS_Image]) -> (CGPoint, CGImage)? {
        let boundingRect = imagesBoundingRect(images: images)
        let start = CACurrentMediaTime()
        guard let cgImage = blendImages(images, boundingRect: boundingRect) else { return nil }
        return (boundingRect.origin, cgImage)
    }

    // MARK: - Private

    private static func blendImages(_ images: [ASS_Image], boundingRect: CGRect) -> CGImage? {
        let buffers = images.compactMap { translateBuffer($0, boundingRect: boundingRect) }
        let composedBuffers = composeBuffers(buffers)
        return makeImage(from: composedBuffers, alphaInfo: .first)
    }

    private static func translateBuffer(_ image: ASS_Image, boundingRect: CGRect) -> vImage.PixelBuffer<vImage.Interleaved8x4>? {
        let width = Int(image.w)
        let height = Int(image.h)
        if width == 0 || height == 0 { return nil }
        guard let size = vImage.Size(exactly: boundingRect.size) else { return nil }
        let destinationBuffer = makePixelBuffer(size: size, fillColor: (0, 0, 0, 0))
        let relativeRect = image.relativeImageRect(to: boundingRect)
        let stride = Int(image.stride)
        let red = UInt8((image.color >> 24) & 0xFF)
        let green = UInt8((image.color >> 16) & 0xFF)
        let blue = UInt8((image.color >> 8) & 0xFF)
        var bitmapPosition = 0
        destinationBuffer.withUnsafeRegionOfInterest(relativeRect) { buffer in
            let rowBytes = (buffer.rowStride * buffer.byteCountPerPixel)
            var vImagePosition = 0
            buffer.withUnsafeMutableBufferPointer { bufferPtr in
                loop(iterations: height) { _ in
                    loop(iterations: width) { x in
                        let alpha = image.bitmap.advanced(by: bitmapPosition + x).pointee
                        let index = vImagePosition + x * buffer.channelCount
                        bufferPtr[index + 0] = alpha
                        bufferPtr[index + 1] = red
                        bufferPtr[index + 2] = green
                        bufferPtr[index + 3] = blue
                    }
                    vImagePosition += rowBytes
                    bitmapPosition += stride
                }
            }
        }
        return destinationBuffer
    }

    private static func composeBuffers(_ buffers: [vImage.PixelBuffer<vImage.Interleaved8x4>]) -> vImage.PixelBuffer<vImage.Interleaved8x4> {
        let destinationBuffer = buffers[0]
        for buffer in buffers.dropFirst() {
            destinationBuffer.alphaComposite(
                .nonpremultiplied,
                topLayer: buffer,
                destination: destinationBuffer
            )
        }

        return destinationBuffer
    }

    private static func makePixelBuffer(size: vImage.Size, fillColor: Pixel_8888) -> vImage.PixelBuffer<vImage.Interleaved8x4> {
        let destinationBuffer = vImage.PixelBuffer(
            size: size,
            pixelFormat: vImage.Interleaved8x4.self
        )
        destinationBuffer.overwriteChannels(
            [0, 1, 2, 3],
            withPixel: fillColor,
            destination: destinationBuffer
        )

        return destinationBuffer
    }

    private static func makeImage(
        from buffer: vImage.PixelBuffer<vImage.Interleaved8x4>,
        alphaInfo: CGImageAlphaInfo
    ) -> CGImage? {
        vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 8 * 4,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue)
        ).flatMap { format in
            buffer.makeCGImage(cgImageFormat: format)
        }
    }
}

extension ASS_Image {
    var imageRect: CGRect {
        let origin = CGPoint(x: Int(dst_x), y: Int(dst_y))
        let size = CGSize(width: Int(w), height: Int(h))

        return CGRect(origin: origin, size: size)
    }

    func relativeImageRect(to boundingRect: CGRect) -> CGRect {
        let rect = imageRect
        let origin = CGPoint(x: rect.minX - boundingRect.minX, y: rect.minY - boundingRect.minY)

        return CGRect(origin: origin, size: rect.size)
    }

    /// Find all the linked images from an `ASS_Image`.
    ///
    /// - Parameters:
    ///   - image: First image from the list.
    ///
    /// - Returns: A  list of `ASS_Image` that should be combined to produce
    /// a final image ready to be drawn on the screen.
    public func linkedImages() -> [ASS_Image] {
        var allImages: [ASS_Image] = []
        var currentImage: ASS_Image? = self
        while let image = currentImage {
            allImages.append(image)
            currentImage = image.next?.pointee
        }

        return allImages
    }
}

/// Find the bounding rect of all linked images.
///
/// - Parameters:
///   - images: Images list to find the bounding rect for.
///
/// - Returns: A `CGRect` containing all image rectangles.
private func imagesBoundingRect(images: [ASS_Image]) -> CGRect {
    let imagesRect = images.map(\.imageRect)
    guard let minX = imagesRect.map(\.minX).min(),
          let minY = imagesRect.map(\.minY).min(),
          let maxX = imagesRect.map(\.maxX).max(),
          let maxY = imagesRect.map(\.maxY).max() else { return .zero }

    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}
