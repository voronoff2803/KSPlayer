//
//  SubtitleLeftView.swift
//  KSPlayer
//
//  Created by Ian Magallan on 29.07.24.
//

import SwiftUI

struct SubtitleLeftView: View {
    let info: SubtitleImageInfo
    let isHDR: Bool

    var body: some View {
        GeometryReader { geometry in
            // 不能加scaledToFit。不然的话图片的缩放比率会有问题。
            let rect = info.displaySize.convert(rect: info.rect, toSize: geometry.size)
            info.image.imageView
                .if(isHDR) {
                    $0.allowedDynamicRange()
                }
                .offset(CGSize(width: rect.origin.x, height: rect.origin.y))
                .frame(width: rect.width, height: rect.height)
        }
    }
}
