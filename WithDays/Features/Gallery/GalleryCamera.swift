import AVFoundation
import SwiftUI

/// The silent camera. Photos are taken from the video stream, not with AVCapturePhotoOutput, so no shutter sound
/// plays (in Japan that one can't be turned off). No audio input, no sounds and no haptics anywhere here.
final class GalleryCameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.ffuime.withdays.gallery.camera")
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private let context = CIContext()
    // On the queue only.
    private var grab: ((CVPixelBuffer) -> Void)?
    private var skip = 0

    func configure(_ position: AVCaptureDevice.Position) async -> AVCaptureDevice? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.setUp(position)) }
        }
    }

    private func setUp(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        if let input { session.removeInput(input) }
        input = nil
        guard let device = Self.device(position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return nil }
        session.addInput(input)
        self.input = input
        if !session.outputs.contains(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            // Saved the right way round, like the iPhone's camera (the preview is mirrored).
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        try? device.lockForConfiguration()
        // The photo preset's own format (a forced high-resolution one exposed too dark); brighter in low light.
        if device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = true }
        // On a camera with an ultra wide, 1× is the wide one.
        if let wide = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            device.videoZoomFactor = CGFloat(truncating: wide)
        } else {
            device.videoZoomFactor = 1
        }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()
        return device
    }

    static func device(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) { return device }
        }
        return nil
    }

    func start() {
        queue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    /// The next frame, turned the way the iPhone is held, as HEIC.
    func photo(angle: CGFloat) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                // Frames already on their way still have the old rotation.
                self.skip = 2
                self.grab = { buffer in
                    continuation.resume(returning: self.encode(buffer))
                }
            }
        }
    }

    private func encode(_ buffer: CVPixelBuffer) -> Data? {
        var image = CIImage(cvPixelBuffer: buffer)
        // A video frame misses the photo pipeline's processing, so it's finished like Photos' auto enhance.
        for filter in image.autoAdjustmentFilters(options: [.redEye: false]) {
            filter.setValue(image, forKey: kCIInputImageKey)
            if let output = filter.outputImage { image = output }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        return context.heifRepresentation(of: image, format: .RGBA8, colorSpace: space, options: [:])
            ?? context.jpegRepresentation(of: image, colorSpace: space, options: [:])
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let grab else { return }
        if skip > 0 {
            skip -= 1
            return
        }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        self.grab = nil
        grab(buffer)
    }

    func torch(_ on: Bool, device: AVCaptureDevice) {
        queue.async {
            guard device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            if on { try? device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) } else { device.torchMode = .off }
            device.unlockForConfiguration()
        }
    }
}

@MainActor
@Observable
final class GalleryCameraModel {
    enum Flash: CaseIterable {
        case auto, on, off

        var symbol: String {
            switch self {
            case .auto: "bolt.badge.automatic"
            case .on: "bolt.fill"
            case .off: "bolt.slash.fill"
            }
        }

        var next: Flash {
            switch self {
            case .auto: .on
            case .on: .off
            case .off: .auto
            }
        }
    }

    var flash = Flash.off
    var position = AVCaptureDevice.Position.back
    var denied = false
    var ready = false
    var zoom: CGFloat = 1
    /// The camera's zoom factors where the lens changes (0.5×, 1×, 3× …).
    var lenses: [CGFloat] = [1]
    /// Turns the camera's zoom factor into what's shown (0.5× for the ultra wide).
    var multiplier: CGFloat = 1
    var minZoom: CGFloat = 1
    var maxZoom: CGFloat = 1
    var last: UIImage?
    var capturing = false
    var blink = false
    var screenFlash = false
    var focusPoint: CGPoint?

    @ObservationIgnored let engine = GalleryCameraEngine()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var coordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored weak var preview: GalleryPreviewUIView?

    func start() async {
        var allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            allowed = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard allowed else {
            denied = true
            return
        }
        await configure()
        engine.start()
    }

    func stop() {
        if let device { engine.torch(false, device: device) }
        engine.stop()
    }

    private func configure() async {
        guard let device = await engine.configure(position) else { return }
        self.device = device
        let factors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let hasUltraWide = device.deviceType == .builtInTripleCamera || device.deviceType == .builtInDualWideCamera
        lenses = hasUltraWide ? [1] + factors : (factors.isEmpty ? [1] : [1] + factors)
        multiplier = device.displayVideoZoomFactorMultiplier
        minZoom = device.minAvailableVideoZoomFactor
        maxZoom = min(device.maxAvailableVideoZoomFactor, 15 / max(multiplier, 0.1))
        zoom = device.videoZoomFactor
        if let layer = preview?.previewLayer {
            coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
            if let connection = layer.connection, let angle = coordinator?.videoRotationAngleForHorizonLevelPreview,
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
        ready = true
    }

    func flip() {
        guard !capturing else { return }
        position = position == .back ? .front : .back
        ready = false
        Task { await configure() }
    }

    func setZoom(_ factor: CGFloat, animated: Bool = false) {
        guard let device else { return }
        let factor = min(max(factor, minZoom), maxZoom)
        zoom = factor
        guard (try? device.lockForConfiguration()) != nil else { return }
        if animated {
            device.ramp(toVideoZoomFactor: factor, withRate: 8)
        } else {
            device.videoZoomFactor = factor
        }
        device.unlockForConfiguration()
    }

    /// Tap to focus and expose there.
    func focus(at point: CGPoint) {
        guard let device, let layer = preview?.previewLayer else { return }
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: point)
        guard (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
            device.focusPointOfInterest = devicePoint
            device.focusMode = .autoFocus
        }
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
            device.exposurePointOfInterest = devicePoint
            device.exposureMode = .autoExpose
        }
        device.isSubjectAreaChangeMonitoringEnabled = true
        device.unlockForConfiguration()
        withAnimation(.snappy) { focusPoint = point }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if focusPoint == point { withAnimation(.easeOut) { focusPoint = nil } }
        }
    }

    func capture(into albumID: String?) {
        guard !capturing, let device else { return }
        capturing = true
        let angle = coordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
        let useFlash = flash == .on || (flash == .auto && isDark(device))
        let front = position == .front
        Task {
            if useFlash {
                if front { screenFlash = true } else { engine.torch(true, device: device) }
                try? await Task.sleep(for: .milliseconds(450))
            }
            let data = await engine.photo(angle: angle)
            if useFlash {
                if front { screenFlash = false } else { engine.torch(false, device: device) }
            }
            // The screen blinks instead of a sound.
            blink = true
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeOut(duration: 0.15)) { blink = false }
            if let data {
                GalleryStore.shared.addCaptured(data, into: albumID)
                last = await Task.detached { UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 160, height: 160)) }.value
            }
            capturing = false
        }
    }

    private func isDark(_ device: AVCaptureDevice) -> Bool {
        device.iso >= device.activeFormat.maxISO * 0.5
    }
}

final class GalleryPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct GalleryCameraPreview: UIViewRepresentable {
    let model: GalleryCameraModel

    func makeUIView(context: Context) -> GalleryPreviewUIView {
        let view = GalleryPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = model.engine.session
        view.previewLayer.videoGravity = .resizeAspectFill
        model.preview = view
        return view
    }

    func updateUIView(_ view: GalleryPreviewUIView, context: Context) {}
}

/// The camera screen, laid out like the iPhone's: flash on top, the 3:4 picture with the lens buttons,
/// then the last photo, the shutter and the flip button.
struct GalleryCameraView: View {
    let albumID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var model = GalleryCameraModel()
    @State private var pinchStart: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                ZStack {
                    GalleryCameraPreview(model: model)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    let start = pinchStart ?? model.zoom
                                    if pinchStart == nil { pinchStart = start }
                                    model.setZoom(start * value.magnification)
                                }
                                .onEnded { _ in pinchStart = nil }
                        )
                        .simultaneousGesture(
                            SpatialTapGesture().onEnded { value in model.focus(at: value.location) }
                        )
                    if let point = model.focusPoint {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.yellow, lineWidth: 1.5)
                            .frame(width: 76, height: 76)
                            .position(point)
                            .transition(.scale(scale: 1.4).combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                    if model.blink {
                        Color.black.allowsHitTesting(false)
                    }
                    VStack {
                        Spacer()
                        lensButtons
                            .padding(.bottom, 14)
                    }
                    if model.denied {
                        ContentUnavailableView("カメラを使えません", systemImage: "camera",
                                               description: Text("設定アプリで WithDays のカメラをオンにしてください。"))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.width * 4 / 3)
                .clipped()
                .frame(maxHeight: .infinity)
            }
            bottomBar
        }
        .background(Color.black.ignoresSafeArea())
        .overlay {
            if model.screenFlash {
                Color.white.ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private var topBar: some View {
        HStack {
            Button {
                model.flash = model.flash.next
            } label: {
                Image(systemName: model.flash.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(model.flash == .on ? Color.yellow : Color.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .accessibilityLabel("フラッシュ")
            Spacer()
            Text("無音")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().stroke(Color.white.opacity(0.4)))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .accessibilityLabel("閉じる")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    /// 0.5 · 1× · 3: the current one shows the exact zoom.
    private var lensButtons: some View {
        let active = model.lenses.lastIndex { model.zoom >= $0 - 0.01 } ?? 0
        return HStack(spacing: 6) {
            ForEach(Array(model.lenses.enumerated()), id: \.offset) { index, factor in
                Button {
                    model.setZoom(factor, animated: true)
                } label: {
                    Text(label(index == active ? model.zoom : factor, current: index == active))
                        .font(.system(size: index == active ? 13 : 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(index == active ? Color.yellow : Color.white)
                        .frame(width: index == active ? 40 : 32, height: index == active ? 40 : 32)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(Color.black.opacity(0.25)))
        .opacity(model.lenses.count > 1 || model.zoom > 1.01 ? 1 : 0)
        .animation(.snappy, value: active)
    }

    private func label(_ factor: CGFloat, current: Bool) -> String {
        let shown = factor * model.multiplier
        let rounded = (shown * 10).rounded() / 10
        let text = rounded < 1 ? String(format: ".%d", Int((rounded * 10).rounded()))
            : (rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded))
        return current ? text + "×" : text
    }

    private var bottomBar: some View {
        HStack {
            Group {
                if let last = model.last {
                    Image(uiImage: last)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.3)))
            Spacer()
            Button {
                model.capture(into: albumID)
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 78, height: 78)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 64, height: 64)
                        .scaleEffect(model.capturing ? 0.88 : 1)
                        .animation(.easeOut(duration: 0.12), value: model.capturing)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!model.ready || model.denied)
            .accessibilityLabel("撮影")
            Spacer()
            Button {
                model.flip()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("カメラを切り替え")
        }
        .padding(.horizontal, 28)
        .frame(height: 130)
    }
}
