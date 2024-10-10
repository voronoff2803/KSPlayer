//
//  GestureView.swift
//
//  Created by WangJun on 2024/10/05.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

public typealias Action = (UISwipeGestureRecognizer.Direction) -> Void

struct GestureView: UIViewRepresentable {

    let swipeAction: Action
    let pressAction: Action
    
    func makeUIView(context: Context) -> UIView {
        return TVGestureHelpView(swipeAction: swipeAction, pressAction: pressAction)
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

public class TVGestureHelpView: UIControl {
    public let swipeAction: Action
    public let pressAction: Action
    
    public init(swipeAction: @escaping Action, pressAction: @escaping Action) {
        self.swipeAction = swipeAction
        self.pressAction = pressAction
        super.init(frame: .zero)
        
        let upSwipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeGesture))
        upSwipeRecognizer.direction = .up
        
        let downSwipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeGesture))
        downSwipeRecognizer.direction = .down
        
        let leftSwipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeGesture))
        leftSwipeRecognizer.direction = .left
        
        let rightSwipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeGesture))
        rightSwipeRecognizer.direction = .right
        
        addGestureRecognizer(upSwipeRecognizer)
        addGestureRecognizer(downSwipeRecognizer)
        addGestureRecognizer(leftSwipeRecognizer)
        addGestureRecognizer(rightSwipeRecognizer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func handleSwipeGesture(gesture: UIGestureRecognizer) {
        guard let swipeGesture = gesture as? UISwipeGestureRecognizer else { return }
        swipeAction(swipeGesture.direction)
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else {
            return
        }
        switch press.type {
        case .upArrow:
            pressAction(.up)
        case .downArrow:
            pressAction(.down)
        case .leftArrow:
            pressAction(.left)
        case .rightArrow:
            pressAction(.right)
        default:
            super.pressesBegan(presses, with: event)
        }
    }
}
#endif