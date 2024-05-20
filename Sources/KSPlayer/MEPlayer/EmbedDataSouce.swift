//
//  EmbedDataSouce.swift
//  KSPlayer-7de52535
//
//  Created by kintan on 2018/8/7.
//
import Foundation
import Libavcodec
import Libavutil

extension FFmpegAssetTrack: SubtitleInfo {
    public var subtitleID: String {
        String(trackID)
    }
}

extension FFmpegAssetTrack: KSSubtitleProtocol {
    public func search(for time: TimeInterval, size: CGSize) async -> [SubtitlePart] {
        if let sutitleRender {
            return await sutitleRender.search(for: time, size: size)
        }
        let array = subtitle?.outputRenderQueue.search { item -> Bool in
            item.part.isEqual(time: time)
        }.map(\.part) ?? []
        return array.map {
            if let (rect, image) = $0.render.left, let displaySize = self.formatDescription?.displaySize {
                let hZoom = size.width / displaySize.width
                let vZoom = size.height / displaySize.height
                let zoom = min(hZoom, vZoom)
                var newRect = rect * zoom
                let newDisplaySize = displaySize * zoom
                newRect.origin.x += (size.width - newDisplaySize.width) / 2
                newRect.origin.y += (size.height - newDisplaySize.height) / 2
                $0.render = .left((newRect.integral, image))
            }
            return $0
        }
    }
}

extension KSMEPlayer: SubtitleDataSouce {
    public var infos: [any SubtitleInfo] {
        tracks(mediaType: .subtitle).compactMap { $0 as? (any SubtitleInfo) }
    }
}
