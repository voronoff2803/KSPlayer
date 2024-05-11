//
//  AssImageParse.swift
//
//
//  Created by kintan on 5/4/24.
//

import Foundation
import libass
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@available(iOS 16.0, tvOS 16.0, visionOS 1.0, macOS 13.0, macCatalyst 16.0, *)
public final class AssImageParse: KSParseProtocol {
    public func canParse(scanner: Scanner) -> Bool {
        guard scanner.scanString("[Script Info]") != nil else {
            return false
        }
        return true
    }

    public func parsePart(scanner _: Scanner) -> SubtitlePart? {
        nil
    }

    public func parse(scanner: Scanner) -> KSSubtitleProtocol {
        AssImageRenderer(content: scanner.string)
    }
}

public final class AssImageRenderer {
    private let library: OpaquePointer?
    private let renderer: OpaquePointer?
    private var currentTrack: UnsafeMutablePointer<ASS_Track>?
    public init(content: String? = nil) {
        library = ass_library_init()
        renderer = ass_renderer_init(library)
        ass_set_extract_fonts(library, 1)
        ass_set_fonts(renderer, nil, nil, Int32(ASS_FONTPROVIDER_FONTCONFIG.rawValue), nil, 1)
        if let content, var buffer = content.cString(using: .utf8) {
            currentTrack = ass_read_memory(library, &buffer, buffer.count, nil)
        } else {
            currentTrack = ass_new_track(library)
        }
        setFrame(size: CGSize(width: 1024, height: 540))
    }

    public func subtitle(header: UnsafeMutablePointer<UInt8>, size: Int32) {
        ass_process_codec_private(currentTrack, header, size)
    }

    public func add(subtitle: UnsafeMutablePointer<CChar>, size: Int32, start: Int64, duration: Int64) {
        ass_process_chunk(currentTrack, subtitle, size, start, duration)
    }

    public func setFrame(size: CGSize) {
        ass_set_frame_size(renderer, Int32(size.width * KSOptions.scale), Int32(size.height * KSOptions.scale))
    }

    deinit {
        currentTrack = nil
        ass_library_done(library)
        ass_renderer_done(renderer)
    }
}

@available(iOS 16.0, tvOS 16.0, visionOS 1.0, macOS 13.0, macCatalyst 16.0, *)
extension AssImageRenderer: KSSubtitleProtocol {
    public func image(for time: TimeInterval, changed: inout Int32) -> ProcessedImage? {
        let millisecond = Int64(time * 1000)
        guard let frame = ass_render_frame(renderer, currentTrack, millisecond, &changed) else {
            return nil
        }
        guard changed != 0 else {
            return nil
        }
        let images = linkedImages(from: frame.pointee)
        let boundingRect = imagesBoundingRect(images: images)
        guard let processedImage = AccelerateImagePipeline.process(images: images, boundingRect: boundingRect) else {
            return nil
        }
        return processedImage
    }

    public func search(for time: TimeInterval, size: CGSize) -> [SubtitlePart] {
        setFrame(size: size)
        var changed = Int32(0)
        guard let processedImage = image(for: time, changed: &changed), let image = processedImage.image.image() else {
            if changed == 0 {
                return []
            } else {
                return [SubtitlePart(time, .infinity, "")]
            }
        }
        let part = SubtitlePart(time, .infinity, image: image)
        return [part]
    }
}

@available(iOS 16.0, tvOS 16.0, visionOS 1.0, macOS 13.0, macCatalyst 16.0, *)
class ASSRender: RenderProtocol {
    private let assImageRenderer: AssImageRenderer
    private let start: TimeInterval
    init(assImageRenderer: AssImageRenderer, start: TimeInterval) {
        self.assImageRenderer = assImageRenderer
        self.start = start
    }

    func render(size: CGSize) -> Either<UIImage, NSAttributedString> {
        assImageRenderer.setFrame(size: size)
        var changed = Int32(0)
        if let cgImage = assImageRenderer.image(for: start, changed: &changed)?.image {
            return .left(UIImage(cgImage: cgImage))
        } else {
            return .right(NSAttributedString())
        }
    }
}
