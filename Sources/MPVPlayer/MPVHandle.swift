//
//  MPVHandle.swift
//
//
//  Created by kintan on 5/2/24.
//

import Foundation
import KSPlayer
import libmpv
import QuartzCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
public class MPVHandle: NSObject {
    var mpv: OpaquePointer? = mpv_create()
    let metalView = MetalView()
    private lazy var queue = DispatchQueue(label: "mpv", qos: .userInitiated)
    override public init() {
        super.init()
        #if DEBUG
        check(status: mpv_request_log_messages(mpv, "debug"))
        #else
        check(status: mpv_request_log_messages(mpv, "no"))
        #endif
        setOption(name: "input-media-keys", value: "yes")
        var layer = metalView.layer
        check(status: mpv_set_option(mpv, MPVOption.Window.wid, MPV_FORMAT_INT64, &layer))
        setOption(name: "subs-match-os-language", value: "yes")
        setOption(name: "subs-fallback", value: "yes")
        setOption(name: MPVOption.GPURendererOptions.gpuApi, value: "vulkan")
//        setOption(name: MPVOption.GPURendererOptions.gpuContext, value: "moltenvk")
        setOption(name: MPVOption.Video.vo, value: "gpu-next")
        setOption(name: MPVOption.Video.hwdec, value: "videotoolbox")
//        setOption(name: MPVOption.ProgramBehavior.ytdl, value: "no")
        check(status: mpv_initialize(mpv))
        mpv_set_wakeup_callback(mpv, { ctx in
            guard let ctx else {
                return
            }
            let `self` = Unmanaged<MPVHandle>.fromOpaque(ctx).takeUnretainedValue()
            self.readEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    private func readEvents() {
        queue.async { [weak self] in
            while let self, let mpv = self.mpv, let event = mpv_wait_event(mpv, 0) {
                if event.pointee.event_id == MPV_EVENT_NONE {
                    break
                }
                self.event(event.pointee)
            }
        }
    }

    open func event(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_SHUTDOWN:
            mpv_destroy(mpv)
            mpv = nil
            KSLog("event: shutdown\n")
        case MPV_EVENT_LOG_MESSAGE:
            if let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.data)) {
                KSLog("[\(String(cString: (msg.pointee.prefix)!))] \(String(cString: (msg.pointee.level)!)): \(String(cString: (msg.pointee.text)!))")
            }
        default:
            if let eventName = mpv_event_name(event.event_id) {
                KSLog("event: \(String(cString: eventName))")
            }
        }
    }
}

extension MPVHandle {
    // MARK: - Command & property

    private func makeCArgs(_ command: MPVCommand, _ args: [String?]) -> [String?] {
        if args.count > 0, args.last == nil {
            KSLog("Command do not need a nil suffix")
        }
        var strArgs = args
        strArgs.insert(command.rawValue, at: 0)
        strArgs.append(nil)
        return strArgs
    }

    // Send arbitrary mpv command.
    func command(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true, returnValueCallback: ((Int32) -> Void)? = nil) {
        guard let mpv else { return }
        var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer {
            for ptr in cargs {
                if ptr != nil {
                    free(UnsafeMutablePointer(mutating: ptr!))
                }
            }
        }
        let returnValue = mpv_command(mpv, &cargs)
        if checkError {
            check(status: returnValue)
        }
        if let cb = returnValueCallback {
            cb(returnValue)
        }
    }

    func command(rawString: String) -> Int32 {
        mpv_command_string(mpv, rawString)
    }

    func asyncCommand(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true, replyUserdata: UInt64) {
        guard let mpv else { return }
        var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer {
            for ptr in cargs {
                if ptr != nil {
                    free(UnsafeMutablePointer(mutating: ptr!))
                }
            }
        }
        let returnValue = mpv_command_async(mpv, replyUserdata, &cargs)
        if checkError {
            check(status: returnValue)
        }
    }

    func observe(property: String, format: mpv_format = MPV_FORMAT_DOUBLE) {
        mpv_observe_property(mpv, 0, property, format)
    }

    // Set property
    func setFlag(_ name: String, _ flag: Bool) {
        guard let mpv else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    func setInt(_ name: String, _ value: Int) {
        guard let mpv else { return }
        var data = Int64(value)
        mpv_set_property(mpv, name, MPV_FORMAT_INT64, &data)
    }

    func setDouble(_ name: String, _ value: Double) {
        guard let mpv else { return }
        var data = value
        mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
    }

    func setFlagAsync(_ name: String, _ flag: Bool) {
        guard let mpv else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property_async(mpv, 0, name, MPV_FORMAT_FLAG, &data)
    }

    func setIntAsync(_ name: String, _ value: Int) {
        guard let mpv else { return }
        var data = Int64(value)
        mpv_set_property_async(mpv, 0, name, MPV_FORMAT_INT64, &data)
    }

    func setDoubleAsync(_ name: String, _ value: Double) {
        guard let mpv else { return }
        var data = value
        mpv_set_property_async(mpv, 0, name, MPV_FORMAT_DOUBLE, &data)
    }

    func setString(_ name: String, _ value: String) {
        guard let mpv else { return }
        mpv_set_property_string(mpv, name, value)
    }

    func getInt(_ name: String) -> Int {
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
        return Int(data)
    }

    func getDouble(_ name: String) -> Double {
        guard let mpv else { return 0.0 }
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }

    func getFlag(_ name: String) -> Bool {
        guard let mpv else { return false }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data > 0
    }

    func getString(_ name: String) -> String? {
        let cstr = mpv_get_property_string(mpv, name)
        let str: String? = cstr == nil ? nil : String(cString: cstr!)
        mpv_free(cstr)
        return str
    }

    func setOption(name: String, value: String) {
        guard let mpv else { return }
        check(status: mpv_set_option_string(mpv, name, value))
    }

    func check(status: CInt) {
        if status < 0 {
            KSLog("MPV API error: \(String(cString: mpv_error_string(status))), Return value: \(status).")
        }
    }
}
