import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import VisionKit

enum ToocQRSheet: String, Identifiable {
    /// Your QR code; 「スキャン」 opens the camera.
    case show
    /// Straight to the camera.
    case scan
    var id: String { rawValue }
}

/// MyQR: the code in the middle, a scan button under it, and buttons to share the link on other apps.
struct ToocQRView: View {
    let start: ToocQRSheet

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var scanning = false
    @State private var scanned: String?
    @State private var copied = false

    /// A stand-in until profiles have real links.
    static let link = URL(string: "https://example.com")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                ToocQRCode(text: Self.link.absoluteString)
                    .frame(width: 240, height: 240)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                Button {
                    scanning = true
                } label: {
                    Label("スキャン", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                Spacer()
                shareRow
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("MyQR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
            .navigationDestination(isPresented: $scanning) {
                ToocScanView { scanned = $0 }
            }
            .alert("読み取りました", isPresented: Binding(get: { scanned != nil }, set: { if !$0 { scanned = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanned ?? "")
            }
            .alert("リンクをコピーしました", isPresented: $copied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Instagram で貼り付けて送れます。")
            }
        }
        .onAppear { if start == .scan { scanning = true } }
    }

    // MARK: Sharing

    private var shareRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                share("LINE", color: Color(red: 0.02, green: 0.78, blue: 0.33), mark: .text("L")) {
                    open("https://line.me/R/share?text=", Self.link.absoluteString)
                }
                share("Instagram", color: Color(red: 0.83, green: 0.16, blue: 0.48), mark: .symbol("camera")) {
                    // Instagram has no link for sharing text: copy it, then open Instagram.
                    UIPasteboard.general.url = Self.link
                    copied = true
                    if let app = URL(string: "instagram://app") {
                        openURL(app) { opened in
                            if !opened, let web = URL(string: "https://www.instagram.com/") { openURL(web) }
                        }
                    }
                }
                share("iMessage", color: Color(red: 0.2, green: 0.78, blue: 0.35), mark: .symbol("message.fill")) {
                    open("sms:&body=", Self.link.absoluteString)
                }
                share("X", color: .black, mark: .text("X")) {
                    open("https://x.com/intent/post?text=", Self.link.absoluteString)
                }
                share("Facebook", color: Color(red: 0.09, green: 0.47, blue: 0.95), mark: .text("f")) {
                    open("https://www.facebook.com/sharer/sharer.php?u=", Self.link.absoluteString)
                }
                ShareLink(item: Self.link) {
                    shareLabel("その他", color: Color(.systemGray), mark: .symbol("square.and.arrow.up"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private enum Mark { case text(String), symbol(String) }

    private func share(_ name: String, color: Color, mark: Mark, action: @escaping () -> Void) -> some View {
        Button(action: action) { shareLabel(name, color: color, mark: mark) }
            .buttonStyle(.plain)
    }

    private func shareLabel(_ name: String, color: Color, mark: Mark) -> some View {
        VStack(spacing: 6) {
            Group {
                switch mark {
                case .text(let text): Text(text).font(.system(size: 22, weight: .heavy, design: .rounded))
                case .symbol(let symbol): Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(color, in: Circle())
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func open(_ prefix: String, _ text: String) {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
        if let url = URL(string: prefix + encoded) { openURL(url) }
    }
}

/// A crisp QR code for some text.
struct ToocQRCode: View {
    let text: String

    var body: some View {
        if let image = Self.make(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("QRコード")
        } else {
            Image(systemName: "qrcode").resizable().scaledToFit()
        }
    }

    static func make(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// The camera, reading the first QR code it sees.
struct ToocScanView: View {
    var onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            if access == .notDetermined {
                ProgressView()
            } else if access == .authorized, DataScannerViewController.isSupported {
                ToocDataScanner { text in
                    onScan(text)
                    dismiss()
                }
                .ignoresSafeArea()
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 240, height: 240)
                        .allowsHitTesting(false)
                }
            } else {
                ContentUnavailableView(
                    "カメラを使えません",
                    systemImage: "camera",
                    description: Text("設定アプリで WithDays のカメラを許可してください。")
                )
            }
        }
        .navigationTitle("スキャン")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Asks for the camera the first time.
            if access == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                access = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }
}

private struct ToocDataScanner: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        DispatchQueue.main.async { try? scanner.startScanning() }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var done = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let text = barcode.payloadStringValue {
                    done = true
                    dataScanner.stopScanning()
                    onScan(text)
                    return
                }
            }
        }
    }
}
