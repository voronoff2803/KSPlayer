//
//  KSParseProtocol.swift
//  KSPlayer-7de52535
//
//  Created by kintan on 2018/8/7.
//
import Foundation
import SwiftUI
#if !canImport(UIKit)
import AppKit
#else
import UIKit
#endif
public protocol KSParseProtocol {
    func canParse(scanner: Scanner) -> Bool
    func parsePart(scanner: Scanner) -> SubtitlePart?
    func parse(scanner: Scanner) -> KSSubtitleProtocol
}

public extension KSOptions {
    static var subtitleParses: [KSParseProtocol] = [AssImageParse(), AssParse(), VTTParse(), SrtParse()]
}

public extension String {}

public extension KSParseProtocol {
    func parse(scanner: Scanner) -> KSSubtitleProtocol {
        var groups = [SubtitlePart]()
        while !scanner.isAtEnd {
            if let group = parsePart(scanner: scanner) {
                groups.append(group)
            }
        }
        groups = groups.mergeSortBottomUp { $0 < $1 }
        return groups
    }
}

extension [SubtitlePart]: KSSubtitleProtocol {
    public func search(for time: TimeInterval, size _: CGSize, isHDR _: Bool) -> [SubtitlePart] {
        var result = [SubtitlePart]()
        for part in self {
            if part == time {
                result.append(part)
            } else if part.start > time {
                break
            }
        }
        return result
    }
}

public class SrtParse: KSParseProtocol {
    public func canParse(scanner: Scanner) -> Bool {
        let result = scanner.string.contains(" --> ")
        if result {
            scanner.charactersToBeSkipped = nil
        }
        return result
    }

    /**
     45
     00:02:52,184 --> 00:02:53,617
     {\an4}慢慢来
     */
    public func parsePart(scanner: Scanner) -> SubtitlePart? {
        if let (start, end, text) = SrtParse.parsePart(scanner: scanner) {
            var textPosition = TextPosition()
            return SubtitlePart(start.parseDuration(), end.parseDuration(), attributedString: text.build(textPosition: &textPosition))
        } else {
            return nil
        }
    }

    public static func parsePart(scanner: Scanner) -> (start: String, end: String, text: String)? {
        var decimal: String?
        repeat {
            decimal = scanner.scanUpToCharacters(from: .newlines)
            _ = scanner.scanCharacters(from: .newlines)
        } while decimal.flatMap(Int.init) == nil
        let startString = scanner.scanUpToString("-->")
        // skip spaces and newlines by default.
        _ = scanner.scanString("-->")
        if let startString,
           let endString = scanner.scanUpToCharacters(from: .newlines)
        {
            _ = scanner.scanCharacters(from: .newlines)
            var text = ""
            var newLine: String? = nil
            repeat {
                if let str = scanner.scanUpToCharacters(from: .newlines) {
                    text += str
                }
                newLine = scanner.scanCharacters(from: .newlines)
                if newLine == "\n" || newLine == "\r\n" {
                    text += "\n"
                }
            } while newLine == "\n" || newLine == "\r\n"
            return (startString, endString, text)
        }
        return nil
    }
}

public class VTTParse: SrtParse {
    override public func canParse(scanner: Scanner) -> Bool {
        let result = scanner.scanString("WEBVTT")
        if result != nil {
            scanner.charactersToBeSkipped = nil
            return true
        } else {
            return false
        }
    }
}

extension Scanner {
    func changeToAss() -> String {
        var ass = """
        [Script Info]
        Script generated by KSPlayer
        ScriptType: v4.00+
        PlayResX: 384
        PlayResY: 288
        ScaledBorderAndShadow: yes
        YCbCr Matrix: None

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        \(KSOptions.assStyle)

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

        """
        while !isAtEnd {
            if let (start, end, text) = SrtParse.parsePart(scanner: self) {
                var start = start.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
                start.removeLast()
                var end = end.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
                end.removeLast()
                ass += "Dialogue: 0,\(start),\(end),Default,,0,0,0,,\(text)\n"
            }
        }
        return ass
    }
}

extension KSOptions {
    static var assStyle: String {
        "Style: Default,Arial,\(textFontSize / 2),&Hffffff,&Hffffff,&H0,&H0,\(textBold ? "1" : "0"),\(textItalic ? "1" : "0"),0,0,100,100,0,0,1,1,0,2,10,10,10,1"
    }
}
