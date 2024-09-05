//
//  AudioRendererPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2022/12/2.
//

import AVFoundation
import Foundation

public class AudioRendererPlayer: AudioOutput {
    public var playbackRate: Float = 1 {
        didSet {
            if !isPaused {
                synchronizer.rate = playbackRate
            }
        }
    }

    public var volume: Float {
        get {
            renderer.volume
        }
        set {
            renderer.volume = newValue
        }
    }

    public var isMuted: Bool {
        get {
            renderer.isMuted
        }
        set {
            renderer.isMuted = newValue
        }
    }

    var isPaused: Bool {
        synchronizer.rate == 0
    }

    public weak var renderSource: OutputRenderSourceDelegate?
    private var periodicTimeObserver: Any?
    private var flushTime = true
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let serializationQueue = DispatchQueue(label: "ks.player.serialization.queue")
    public required init() {
        synchronizer.addRenderer(renderer)
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *) {
            synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        }
//        if #available(tvOS 15.0, iOS 15.0, macOS 12.0, *) {
//            renderer.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
//        }
    }

    public func prepare(audioFormat: AVAudioFormat) {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        KSLog("[audio] set preferredOutputNumberOfChannels: \(audioFormat.channelCount)")
        #endif
    }

    public func play() {
        let time: CMTime
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *), renderer.hasSufficientMediaDataForReliablePlaybackStart {
            // 判断是否有足够的缓存，有的话就用当前的时间。seek的话，需要清空缓存，这样才能取到最新的时间。
            time = synchronizer.currentTime()
        } else {
            /// 连接蓝牙音响的话，hasSufficientMediaDataForReliablePlaybackStart会一直返回false,
            /// 所以要兜底判断要不要从数据源头获取最新的时间，
            if flushTime, let currentRender = renderSource?.getAudioOutputRender() {
                flushTime = false
                time = currentRender.cmtime
            } else {
                time = synchronizer.currentTime()
            }
        }
        // 一定要用setRate(_ rate: Float, time: CMTime)，只改rate是无法进行播放的
        synchronizer.setRate(playbackRate, time: time)
        renderSource?.setAudio(time: time, position: -1)
        renderer.requestMediaDataWhenReady(on: serializationQueue) { [weak self] in
            guard let self else {
                return
            }
            self.request()
        }
        periodicTimeObserver = synchronizer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.01), queue: .main) { [weak self] time in
            guard let self else {
                return
            }
            self.renderSource?.setAudio(time: time, position: -1)
        }
    }

    public func pause() {
        synchronizer.rate = 0
        renderer.stopRequestingMediaData()
        if let periodicTimeObserver {
            synchronizer.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
    }

    public func flush() {
        renderer.flush()
        flushTime = true
    }

    private func request() {
        guard !isPaused, var render = renderSource?.getAudioOutputRender() else {
            return
        }
        var array = [render]
        let loopCount = Int32(render.audioFormat.sampleRate) / 20 / Int32(render.numberOfSamples) - 2
        if loopCount > 0 {
            for _ in 0 ..< loopCount {
                if let render = renderSource?.getAudioOutputRender() {
                    array.append(render)
                }
            }
        }
        if array.count > 1 {
            render = AudioFrame(array: array)
        }
        if let sampleBuffer = render.toCMSampleBuffer() {
            let channelCount = render.audioFormat.channelCount
            renderer.audioTimePitchAlgorithm = channelCount > 2 ? .spectral : .timeDomain
            renderer.enqueue(sampleBuffer)
            #if !os(macOS)
            if AVAudioSession.sharedInstance().preferredInputNumberOfChannels != channelCount {
                try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(channelCount))
            }
            #endif
        }
        /// 连接蓝牙音响的话， 要缓存100多秒isReadyForMoreMediaData才会返回false，
        /// 非蓝牙音响只要1.3s就返回true了。还没找到解决办法
//        if !renderer.isReadyForMoreMediaData {
//            let diff = render.seconds - synchronizer.currentTime().seconds
//            KSLog("[audio] AVSampleBufferAudioRenderer cache \(diff)")
//        }
    }
}
