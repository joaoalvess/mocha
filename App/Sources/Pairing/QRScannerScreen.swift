import AVFoundation
import MochaClient
import MochaProtocol
import OSLog
import SwiftUI
import VisionKit

private let scannerLogger = Logger(subsystem: "com.joaoalves.mocha", category: "pairing")

struct QRScannerScreen: View {
    let onScan: (PairingLink) -> Void
    let onClose: () -> Void

    @State private var camera = CameraState.checking
    @State private var scannedHost: String?

    var body: some View {
        ZStack(alignment: .top) {
            Palette.black.ignoresSafeArea()
            if camera == .ready {
                QRDataScanner(onPayload: handle)
                    .ignoresSafeArea()
            }
            Text("Ler QR do mochad")
                .font(.system(size: 17, weight: .semibold))
                .systemLinePitch(22, size: 17)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 81)
            Text("No Mac: \(PairingCode.text("mochad pair", color: Palette.textPrimary))")
                .font(.system(size: 14))
                .systemLinePitch(19, size: 14)
                .foregroundStyle(Palette.cameraSubtitle)
                .padding(.top, 107)
            QRReticle(isRecognized: scannedHost != nil)
                .padding(.top, 191)
            if let message = camera.message {
                Text(message)
                    .font(.system(size: 15))
                    .systemLinePitch(21, size: 15)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 200, height: 234)
                    .padding(.top, 191)
            }
            if let host = scannedHost {
                PairingProgressPill(text: "Conectando ao \(host)…")
                    .padding(.top, 513)
                    .transition(.opacity)
            }
            HStack {
                GlassRoundButton(systemImage: "xmark", accessibilityLabel: "Fechar", style: .black, action: onClose)
                Spacer()
            }
            .padding(.leading, Metrics.contentMargin)
            .padding(.top, 8)
        }
        .animation(.smooth(duration: 0.2), value: scannedHost)
        .task {
            camera = await CameraState.current()
        }
    }

    private func handle(_ payload: String) {
        guard scannedHost == nil, let url = URL(string: payload), let link = PairingLink(url) else { return }
        scannedHost = PairingGate.displayName(for: link.url)
        onScan(link)
    }
}

private enum CameraState: Equatable {
    case checking
    case ready
    case unsupported
    case denied

    var message: String? {
        switch self {
        case .checking, .ready: nil
        case .unsupported: "Este aparelho não lê QR pela câmera. Cole o link do mochad pair."
        case .denied: "Permita o acesso à câmera nos Ajustes do iPhone para ler o QR."
        }
    }

    @MainActor
    static func current() async -> CameraState {
        guard DataScannerViewController.isSupported else { return .unsupported }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        return DataScannerViewController.isAvailable ? .ready : .denied
    }
}

private struct QRReticle: View {
    let isRecognized: Bool

    private static let side: CGFloat = 234
    private static let corner: CGFloat = 46

    var body: some View {
        let color = isRecognized ? Palette.statusOk : Palette.textPrimary
        ZStack {
            ForEach(Array([0.0, 90, 180, 270].enumerated()), id: \.offset) { _, angle in
                QRReticleCorner()
                    .stroke(color, lineWidth: 4)
                    .frame(width: Self.corner, height: Self.corner)
                    .frame(width: Self.side, height: Self.side, alignment: .topLeading)
                    .rotationEffect(.degrees(angle))
            }
        }
        .frame(width: Self.side, height: Self.side)
        .shadow(color: isRecognized ? Palette.statusOk.opacity(0.5) : .clear, radius: 3)
        .animation(.smooth(duration: 0.2), value: isRecognized)
        .accessibilityHidden(true)
    }
}

private struct QRReticleCorner: Shape {
    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 2
        let radius: CGFloat = 16
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset + radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + inset, y: rect.minY + inset),
            tangent2End: CGPoint(x: rect.minX + inset + radius, y: rect.minY + inset),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + inset))
        return path
    }
}

private struct QRDataScanner: UIViewControllerRepresentable {
    let onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onPayload = onPayload
        guard !scanner.isScanning else { return }
        do {
            try scanner.startScanning()
        } catch {
            scannerLogger.error("could not start the QR scanner: \(String(describing: error), privacy: .public)")
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onPayload: (String) -> Void

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onPayload(payload)
                }
            }
        }
    }
}
