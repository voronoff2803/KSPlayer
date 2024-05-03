//
//  KSMPVPlayer.swift
//
//
//  Created by kintan on 5/2/24.
//

import AVFoundation
import CoreGraphics
import Dispatch
import Foundation
import KSPlayer
import libmpv
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
public class KSMPVPlayer: MPVHandle {
    public weak var delegate: MediaPlayerDelegate?
    public var allowsExternalPlayback: Bool = false
    public var usesExternalPlaybackWhileExternalScreenIsActive: Bool = false
    public private(set) var isReadyToPlay = false
    public private(set) var playbackState = MediaPlaybackState.idle
    public private(set) var loadState = MediaLoadState.idle
    public var duration: TimeInterval = 0
    public var fileSize: Double = 0
    public var naturalSize: CGSize = .zero
    private lazy var _playbackCoordinator: Any? = {
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, *) {
            let coordinator = AVDelegatingPlaybackCoordinator(playbackControlDelegate: self)
            coordinator.suspensionReasonsThatTriggerWaiting = [.stallRecovery]
            return coordinator
        } else {
            return nil
        }
    }()

    private var tracks = [MPVTrack]()
    private var bufferingCountDownTimer: Timer?
    private let url: URL
    @MainActor
    public required init(url: URL, options _: KSOptions) {
        self.url = url
        super.init()
    }

    override public func event(_ event: mpv_event) {
        super.event(event)
        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            sourceDidOpened()
        default:
            break
        }
    }

    func sourceDidOpened() {
        isReadyToPlay = true
        duration = getDouble(MPVProperty.duration)
        fileSize = getDouble(MPVProperty.fileSize)
        naturalSize = CGSize(width: getInt(MPVProperty.width), height: getInt(MPVProperty.height))
        let trackCount = getInt(MPVProperty.trackListCount)
        tracks = (0 ..< trackCount).compactMap { index in
            guard let trackType = getString(MPVProperty.trackListNType(index)) else {
                return nil
            }
            let mediaType = AVMediaType(rawValue: trackType)
            let track = MPVTrack(trackID: Int32(getInt(MPVProperty.trackListNId(index))), name: getString(MPVProperty.trackListNTitle(index)) ?? "", mediaType: mediaType, nominalFrameRate: Float(getDouble(MPVProperty.trackListNDemuxFps(index))), bitRate: 0, bitDepth: 0, isEnabled: getFlag(MPVProperty.trackListNSelected(index)), isImageSubtitle: false, rotation: 0, fieldOrder: .unknown, description: getString(MPVProperty.trackListNDecoderDesc(index)) ?? "")
            track.languageCode = getString(MPVProperty.trackListNLang(index))
            return track
        }
        runOnMainThread { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.readyToPlay(player: self)
        }
    }
}

extension KSMPVPlayer: MediaPlayerProtocol {
    public var view: UIView? {
        metalView
    }

    public var playableTime: TimeInterval {
        1
    }

    public var seekable: Bool {
        getFlag(MPVProperty.seekable)
    }

    public var isMuted: Bool {
        get {
            getFlag(MPVOption.Audio.mute)
        }
        set(newValue) {
            setFlag(MPVOption.Audio.mute, newValue)
        }
    }

    public var playbackRate: Float {
        get {
            Float(getDouble(MPVOption.PlaybackControl.speed))
        }
        set(newValue) {
            setDouble(MPVOption.PlaybackControl.speed, Double(newValue))
        }
    }

    public var playbackVolume: Float {
        get {
            Float(getDouble(MPVOption.Audio.volume))
        }
        set(newValue) {
            setDouble(MPVOption.Audio.volume, Double(newValue))
        }
    }

    public var subtitleDataSouce: (any KSPlayer.SubtitleDataSouce)? {
        nil
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
    public var playbackCoordinator: AVPlaybackCoordinator {
        // swiftlint:disable force_cast
        _playbackCoordinator as! AVPlaybackCoordinator
        // swiftlint:enable force_cast
    }

    @available(tvOS 14.0, *)
    public var pipController: KSPlayer.KSPictureInPictureController? {
        nil
    }

    public var dynamicInfo: KSPlayer.DynamicInfo? {
        nil
    }

    public func replace(url _: URL, options _: KSPlayer.KSOptions) {}

    public func play() {
        playbackState = .playing
        setFlagAsync(MPVOption.PlaybackControl.pause, false)
    }

    public func pause() {
        playbackState = .paused
        setFlagAsync(MPVOption.PlaybackControl.pause, true)
    }

    public func enterBackground() {}

    public func enterForeground() {}

    public func thumbnailImageAtCurrentTime() async -> CGImage? {
        nil
    }

    public func tracks(mediaType: AVMediaType) -> [any KSPlayer.MediaPlayerTrack] {
        tracks.filter { $0.mediaType == mediaType }
    }

    public func select(track _: some KSPlayer.MediaPlayerTrack) {}

    public var chapters: [KSPlayer.Chapter] {
        []
    }

    public var currentPlaybackTime: TimeInterval {
        getDouble(MPVProperty.timePos)
    }

    public func prepareToPlay() {
        let urlString: String
        if url.isFileURL {
            urlString = url.path
        } else {
            urlString = url.absoluteString
        }
        var args = [url.absoluteString]
        var options = [String]()
        args.append("replace")
        if !options.isEmpty {
            args.append(options.joined(separator: ","))
        }
        command(.loadfile, args: args)
    }

    public func shutdown() {
        command(.stop)
        mpv_set_wakeup_callback(mpv, nil, nil)
    }

    public func seek(time _: TimeInterval, completion _: @escaping ((Bool) -> Void)) {
        command(.seek, args: ["\(time)", "absolute+exact"])
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
extension KSMPVPlayer: AVPlaybackCoordinatorPlaybackControlDelegate {
    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue playCommand: AVDelegatingPlaybackCoordinatorPlayCommand, completionHandler: @escaping () -> Void) {
        guard playCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            completionHandler()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if self.playbackState != .playing {
                self.play()
            }
            completionHandler()
        }
    }

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue pauseCommand: AVDelegatingPlaybackCoordinatorPauseCommand, completionHandler: @escaping () -> Void) {
        guard pauseCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            completionHandler()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if self.playbackState != .paused {
                self.pause()
            }
            completionHandler()
        }
    }

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue seekCommand: AVDelegatingPlaybackCoordinatorSeekCommand) async {
        guard seekCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            return
        }
        let seekTime = fmod(seekCommand.itemTime.seconds, duration)
        if abs(currentPlaybackTime - seekTime) < CGFLOAT_EPSILON {
            return
        }
        seek(time: seekTime) { _ in }
    }

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue bufferingCommand: AVDelegatingPlaybackCoordinatorBufferingCommand, completionHandler: @escaping () -> Void) {
        guard bufferingCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            completionHandler()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            guard self.loadState != .playable, let countDown = bufferingCommand.completionDueDate?.timeIntervalSinceNow else {
                completionHandler()
                return
            }
            self.bufferingCountDownTimer?.invalidate()
            self.bufferingCountDownTimer = nil
            self.bufferingCountDownTimer = Timer(timeInterval: countDown, repeats: false) { _ in
                completionHandler()
            }
        }
    }
}

public class MPVTrack: MediaPlayerTrack {
    public var trackID: Int32
    public var name: String
    public var mediaType: AVMediaType

    public var nominalFrameRate: Float

    public var bitRate: Int64

    public var bitDepth: Int32

    public var isEnabled: Bool

    public var isImageSubtitle: Bool

    public var rotation: Int16

    public var fieldOrder: KSPlayer.FFmpegFieldOrder
    public var description: String
    public var languageCode: String? = nil
    public var formatDescription: CMFormatDescription? = nil
    public var dovi: KSPlayer.DOVIDecoderConfigurationRecord? = nil
    init(trackID: Int32, name: String, mediaType: AVMediaType, nominalFrameRate: Float, bitRate: Int64, bitDepth: Int32, isEnabled: Bool, isImageSubtitle: Bool, rotation: Int16, fieldOrder: KSPlayer.FFmpegFieldOrder, description: String) {
        self.trackID = trackID
        self.name = name
        self.mediaType = mediaType
        self.nominalFrameRate = nominalFrameRate
        self.bitRate = bitRate
        self.bitDepth = bitDepth
        self.isEnabled = isEnabled
        self.isImageSubtitle = isImageSubtitle
        self.rotation = rotation
        self.fieldOrder = fieldOrder
        self.description = description
    }
}
