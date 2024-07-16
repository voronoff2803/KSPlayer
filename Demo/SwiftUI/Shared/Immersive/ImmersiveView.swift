//
//  ImmersiveView.swift
//  Player
//
//  Created by BM on 2024/7/16.
//

import Combine
import KSPlayer
import RealityKit
import SwiftUI

#if os(visionOS)
struct ImmersiveView: View {
    @Binding var url: String?

    @State var view: KSMEPlayer?

    var body: some View {
        RealityView { content in
            if let url =  URL(string: url ?? "") {
                let options = KSOptions()
                let player = KSMEPlayer(url: url, options: options)
                view = player

                if let displayLayer = player.videoOutput?.displayLayer {
                    let videoEntity = Entity()
                    let material = VideoMaterial(videoRenderer: displayLayer.sampleBufferRenderer)
                    let boxMesh = MeshResource.generatePlane(width: 16, height: 9)
                    videoEntity.components.set(ModelComponent(mesh: boxMesh, materials: [material]))

                    videoEntity.transform.translation = [0, 2.5, -5]
                    content.add(videoEntity)
                    // 播放视频
                    player.prepareToPlay()
                    player.play()
                }
            }
        }
        .onDisappear {
            view = nil
        }
    }
}
#endif
