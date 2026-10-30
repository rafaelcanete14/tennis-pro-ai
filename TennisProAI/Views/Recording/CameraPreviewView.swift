import SwiftUI
import AVFoundation
import UIKit

final class PreviewContainerUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        // Safe cast because layerClass is overridden to AVCaptureVideoPreviewLayer
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let isSimulated: Bool

    func makeUIView(context: Context) -> PreviewContainerUIView {
        let view = PreviewContainerUIView()
        view.backgroundColor = UIColor(red: 0.05, green: 0.14, blue: 0.12, alpha: 1.0)
        if !isSimulated {
            view.videoPreviewLayer.session = session
            view.videoPreviewLayer.videoGravity = .resizeAspectFill
            if let connection = view.videoPreviewLayer.connection,
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewContainerUIView, context: Context) {
        if !isSimulated && uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }
}

/// Optional tripod court-alignment guide lines helping players mount their iPhone squarely behind the baseline fence.
struct CourtAlignmentGuideOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Canvas { context, _ in
                var path = Path()
                // Perspective baseline trapezoid & net horizon reference
                let topY = h * 0.34
                let bottomY = h * 0.84
                path.move(to: CGPoint(x: w * 0.24, y: topY))
                path.addLine(to: CGPoint(x: w * 0.76, y: topY))
                path.addLine(to: CGPoint(x: w * 0.90, y: bottomY))
                path.addLine(to: CGPoint(x: w * 0.10, y: bottomY))
                path.closeSubpath()

                // Center service line
                path.move(to: CGPoint(x: w * 0.50, y: topY))
                path.addLine(to: CGPoint(x: w * 0.50, y: bottomY))

                // Net horizon line
                path.move(to: CGPoint(x: w * 0.16, y: h * 0.54))
                path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.54))

                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.32)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                )
            }
            .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }
}

