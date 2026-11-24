import SwiftUI
import UIKit

/// Full-screen touch surface that reports UITouch.timestamp (seconds since boot, the same clock as
/// the motion samples). SwiftUI's tap gesture fires on touch-up and has no timestamp, which would
/// add the finger's contact time to every reaction time.
struct TapCatcher: UIViewRepresentable {
    let onTouchDown: (Double) -> Void

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.onTouchDown = onTouchDown
        v.isMultipleTouchEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.onTouchDown = onTouchDown
    }

    final class TouchView: UIView {
        var onTouchDown: ((Double) -> Void)?
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let t = touches.first?.timestamp { onTouchDown?(t) }
        }
    }
}
