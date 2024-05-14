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
        if let assImageRenderer {
            if #available(iOS 16.0, tvOS 16.0, visionOS 1.0, macOS 13.0, macCatalyst 16.0, *) {
                return await assImageRenderer.search(for: time, size: size)
            } else {
                return []
            }
        }
        var array = subtitle?.outputRenderQueue.search { item -> Bool in
            item.part.isEqual(time: time)
        }.map(\.part) ?? []
        return await array.asyncMap { await $0.render(size: size) }
    }
}

extension KSMEPlayer: SubtitleDataSouce {
    public var infos: [any SubtitleInfo] {
        tracks(mediaType: .subtitle).compactMap { $0 as? (any SubtitleInfo) }
    }
}
