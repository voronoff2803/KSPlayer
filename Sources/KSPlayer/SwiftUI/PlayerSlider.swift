//
//  PlayerSlider.swift
//
//  Created by WangJun on 2024/8/21.
//

import Foundation
import SwiftUI

@available(iOS 15, tvOS 15, macOS 12, *)
struct PlayerSlider: View {
    let value: Binding<Float>
    let bufferValue: State<Float>?
    let bounds: ClosedRange<Float>
    let onEditingChanged: (Bool) -> Void
    // 是否允许从进度条的任意位置进行点击定位或者拖动定位
    let dragFromAnyPosition: Bool = true

    // 圆点大小
    let thumbSize: CGSize = .init(width: 15, height: 15)
    // 交互面积，比圆点要大一些
    let interactiveSize: CGSize = .init(width: 25, height: 25)
    // 轨道高度
    let trackHeight: CGFloat = 5

    // 圆点颜色
    let thumbColor = Color.white
    // 轨道颜色
    let trackColor = Color.white.opacity(0.5)
    // 播放进度颜色
    let progressColor = Color.green.opacity(0.8)
    // 缓存进度颜色
    let bufferColor = Color.white.opacity(0.9)

    @State
    private var beginDrag = false
    @FocusState
    private var isFocused: Bool
    public init(value: Binding<Float>, bufferValue: State<Float>? = nil, in bounds: ClosedRange<Float> = 0 ... 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.value = value
        self.bufferValue = bufferValue
        self.bounds = bounds
        self.onEditingChanged = onEditingChanged
    }

    func fullTrack() -> some View {
        Capsule()
            .fill(trackColor)
            #if !os(tvOS)
            .frame(height: trackHeight)
            .frame(height: interactiveSize.height)
            #endif
    }

    var body: some View {
        GeometryReader { geometry in
            // 整个进度条
            if dragFromAnyPosition {
                fullTrack()
                #if !os(tvOS)
                    .background(.white.opacity(0.001)) // 需要一个背景，不然interactiveSize的触控范围不会生效
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gestureValue in
                                let computedValue = valueFrom(
                                    distance: Float(gestureValue.location.x),
                                    availableDistance: Float(geometry.size.width),
                                    bounds: bounds,
                                    leadingOffset: Float(thumbSize.width) / 2,
                                    trailingOffset: Float(thumbSize.width) / 2
                                )
                                value.wrappedValue = computedValue
                                if !beginDrag {
                                    beginDrag = true
                                    onEditingChanged(true)
                                }
                            }
                            .onEnded { _ in
                                beginDrag = false
                                onEditingChanged(false)
                            }
                    )

                #endif
            } else {
                fullTrack()
            }
            #if os(tvOS)
            TVOSSlide(value: value, bounds: bounds, isFocused: _isFocused, onEditingChanged: onEditingChanged)
                .focused($isFocused)
            #endif
            // 进度部分
            ProgressTrack(value: value, bufferValue: bufferValue, bounds: bounds, thumbSize: thumbSize, progressColor: progressColor, bufferColor: bufferColor)
                .allowsHitTesting(false)
            #if !os(tvOS)

                .frame(height: trackHeight)
                .frame(height: interactiveSize.height)
            #endif
            // 圆点
            #if !os(tvOS)
            Circle()
                .fill(thumbColor)
                .frame(width: thumbSize.width, height: thumbSize.height)
                .frame(minWidth: interactiveSize.width, minHeight: interactiveSize.height)
                .background(.white.opacity(0.001)) // 需要一个背景，不然interactiveSize的触控范围不会生效
                .position(
                    x: distanceFrom(
                        value: value.wrappedValue,
                        availableDistance: Float(geometry.size.width),
                        bounds: bounds,
                        leadingOffset: Float(thumbSize.width) / 2,
                        trailingOffset: Float(thumbSize.width) / 2
                    ),
                    y: geometry.size.height / 2
                )
                .gesture(
                    DragGesture(minimumDistance: 1) // 这里不要设置成0，不然不小心碰到圆点就会定位
                        .onChanged { gestureValue in
                            let computedValue = valueFrom(
                                distance: Float(gestureValue.location.x),
                                availableDistance: Float(geometry.size.width),
                                bounds: bounds,
                                leadingOffset: Float(thumbSize.width) / 2,
                                trailingOffset: Float(thumbSize.width) / 2
                            )
                            value.wrappedValue = computedValue
                            if !beginDrag {
                                beginDrag = true
                                onEditingChanged(true)
                            }
                        }
                        .onEnded { _ in
                            beginDrag = false
                            onEditingChanged(false)
                        }
                )
            #endif
        }
        .frame(height: interactiveSize.height)
        #if os(macOS)
            .background {
                // mac上面拖动进度条时整个窗口都会被拖动，这样可以临时解决，以后有更好的方法再改下
                Button {} label: {
                    Color.clear
                }
            }
        #endif
    }
}

private struct ProgressTrack: View {
    let value: Binding<Float>
    let bufferValue: State<Float>?

    let bounds: ClosedRange<Float>
    let thumbSize: CGSize
    let progressColor: Color
    let bufferColor: Color

    func maskView(geometry: GeometryProxy, value: Float, offset: Float) -> some View {
        Capsule()
            .frame(
                width: distanceFrom(
                    value: value,
                    availableDistance: Float(geometry.size.width),
                    bounds: bounds,
                    leadingOffset: offset,
                    trailingOffset: offset
                )
            )
            .frame(width: geometry.size.width, alignment: .leading)
    }

    public var body: some View {
        GeometryReader { geometry in
            if let bufferValue {
                Capsule().fill(bufferColor).mask(maskView(geometry: geometry, value: bufferValue.wrappedValue, offset: 0))
            }
            Capsule().fill(progressColor)
            #if os(tvOS) // TV上面没有圆点，不需要间距
                .mask(maskView(geometry: geometry, value: value.wrappedValue, offset: 0))
            #else
                .mask(maskView(geometry: geometry, value: value.wrappedValue, offset: Float(thumbSize.width) / 2))
            #endif
        }
    }
}

private func distanceFrom(value: Float, availableDistance: Float, bounds: ClosedRange<Float> = 0.0 ... 1.0, leadingOffset: Float = 0, trailingOffset: Float = 0) -> CGFloat {
    guard availableDistance > leadingOffset + trailingOffset else { return 0 }
    let boundsLenght = bounds.upperBound - bounds.lowerBound
    let relativeValue = (value - bounds.lowerBound) / boundsLenght
    let offset = (leadingOffset - ((leadingOffset + trailingOffset) * relativeValue))
    return CGFloat(offset + (availableDistance * relativeValue))
}

private func valueFrom(distance: Float, availableDistance: Float, bounds: ClosedRange<Float> = 0.0 ... 1.0, step: Float = 0.001, leadingOffset: Float = 0, trailingOffset: Float = 0) -> Float {
    let relativeValue = (distance - leadingOffset) / (availableDistance - (leadingOffset + trailingOffset))
    let newValue = bounds.lowerBound + (relativeValue * (bounds.upperBound - bounds.lowerBound))
    let steppedNewValue = (round(newValue / step) * step)
    let validatedValue = min(bounds.upperBound, max(bounds.lowerBound, steppedNewValue))
    return validatedValue
}
