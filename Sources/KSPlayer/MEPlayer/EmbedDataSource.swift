//
//  EmbedDataSource.swift
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
    public func search(for time: TimeInterval, size: CGSize, isHDR: Bool) async -> [SubtitlePart] {
        if let subtitleRender {
            return await subtitleRender.search(for: time, size: size, isHDR: isHDR)
        }
        return subtitle?.outputRenderQueue.search { item -> Bool in
            item.part.isEqual(time: time)
        }.map(\.part) ?? []
    }
}

extension KSMEPlayer: EmbedSubtitleDataSource {
    public var infos: [FFmpegAssetTrack] {
        tracks(mediaType: .subtitle).compactMap { $0 as? FFmpegAssetTrack }
    }
}
