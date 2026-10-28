//
//  QRScannerView.swift
//  diplomski
//

import SwiftUI
import AVFoundation

/// A code as it came off the scanner, unparsed.
///
/// The raw string matters: a signed pass is verified against the exact bytes that
/// were scanned, so the mint address must be extracted *after* the signature check
/// rather than pulled out here.
struct ScannedTicket: Identifiable {
    let id = UUID()
    let rawCode: String
}

enum ScannerError: LocalizedError {
    case accessDenied
    case noCameraAvailable
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Camera access is turned off for RushGuard. Enable it in Settings › Privacy › Camera to scan tickets."
        case .noCameraAvailable:
            return "No camera is available on this device."
        case .configurationFailed(let detail):
            return "The camera could not be started: \(detail)"
        }
    }
}

// MARK: - Public entry point

/// Ticket scanner for the admin. Never crashes: every failure path — denied
/// permission, missing hardware, simulator — falls back to manual entry of a
/// mint address, so the whole verification flow stays reachable.
struct QRScannerView: View {
    var completion: (Result<String, Error>) -> Void
    var onCancel: (() -> Void)?

    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var cameraError: ScannerError?
    @State private var isRequestingAccess = false

    /// The camera is unavailable on the simulator, so the manual-entry panel is shown
    /// instead and the admin flow remains usable without a physical device.
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if isSimulator {
                ManualEntryView(
                    reason: "Running in the simulator, where no camera exists. Paste a mint address to run the same verification the scanner performs.",
                    completion: completion,
                    onCancel: onCancel
                )
            } else if let cameraError {
                ManualEntryView(
                    reason: cameraError.localizedDescription,
                    showsSettingsLink: cameraError.isPermissionProblem,
                    completion: completion,
                    onCancel: onCancel
                )
            } else {
                switch authorizationStatus {
                case .authorized:
                    CameraScannerView(
                        onScan: { completion(.success($0)) },
                        onError: { cameraError = $0 },
                        onCancel: onCancel
                    )
                case .notDetermined:
                    RequestingAccessView(isRequesting: isRequestingAccess)
                        .task { await requestAccess() }
                default:
                    ManualEntryView(
                        reason: ScannerError.accessDenied.localizedDescription,
                        showsSettingsLink: true,
                        completion: completion,
                        onCancel: onCancel
                    )
                }
            }
        }
    }

    private func requestAccess() async {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        isRequestingAccess = false
        authorizationStatus = granted ? .authorized : .denied
    }
}

private extension ScannerError {
    var isPermissionProblem: Bool {
        if case .accessDenied = self { return true }
        return false
    }
}

// MARK: - Waiting on the permission prompt

private struct RequestingAccessView: View {
    let isRequesting: Bool
    @Environment(\.theme) var theme

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            VStack(spacing: Layout.Spacing.md) {
                Image(systemName: "camera.viewfinder")
                    .font(theme.typography.iconLarge)
                    .foregroundColor(theme.colors.onSurfaceVariant)
                Text("Waiting for camera permission…")
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurfaceVariant)
                if isRequesting {
                    ProgressView()
                }
            }
        }
    }
}

// MARK: - Manual entry fallback

/// Fallback panel shown whenever the camera cannot be used. Accepts either a
/// bare mint address or a full `rushguard://verify?mint=…` payload, so a QR
/// string copied from anywhere can be pasted straight in.
private struct ManualEntryView: View {
    let reason: String
    var showsSettingsLink: Bool = false
    let completion: (Result<String, Error>) -> Void
    var onCancel: (() -> Void)?

    @State private var enteredValue = ""
    @Environment(\.theme) var theme

    private var trimmedValue: String {
        enteredValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                VStack(spacing: Layout.Spacing.lg) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(theme.typography.iconLarge)
                        .foregroundColor(theme.colors.onSurfaceVariant)

                    Text(reason)
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if showsSettingsLink, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: settingsURL)
                            .font(theme.typography.labelMedium)
                            .foregroundColor(theme.colors.primary)
                    }

                    Divider().padding(.horizontal)

                    VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                        Text("MINT ADDRESS OR QR PAYLOAD")
                            .font(theme.typography.labelSmall)
                            .foregroundColor(theme.colors.onSurfaceVariant)

                        TextField("Paste here", text: $enteredValue, axis: .vertical)
                            .font(theme.typography.monoBody)
                            .foregroundColor(theme.colors.onSurface)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .lineLimit(1...4)
                            .padding()
                            .background(theme.colors.surfaceContainerHigh)
                            .cornerRadius(Layout.Radius.md)
                    }
                    .padding(.horizontal)

                    Button {
                        completion(.success(trimmedValue))
                    } label: {
                        Text("Verify Ticket")
                            .font(theme.typography.bodyLarge)
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(trimmedValue.isEmpty ? theme.colors.surfaceContainerHigh : theme.colors.primary)
                            .foregroundColor(trimmedValue.isEmpty ? theme.colors.onSurfaceVariant : .white)
                            .cornerRadius(Layout.Radius.xl)
                    }
                    .disabled(trimmedValue.isEmpty)
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, Layout.Spacing.xl)
            }
            .navigationTitle("Simulate Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { onCancel?() }
                }
            }
        }
    }
}

// MARK: - Live camera

private struct CameraScannerView: View {
    let onScan: (String) -> Void
    let onError: (ScannerError) -> Void
    var onCancel: (() -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            CameraPreview(onScan: onScan, onError: onError)
                .ignoresSafeArea()

            HStack {
                Button {
                    onCancel?()
                } label: {
                    Text("Cancel")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
            }
            .padding()

            VStack {
                Spacer()
                Text("Point the camera at a ticket QR code")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 48)
            }
        }
    }
}

private struct CameraPreview: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (ScannerError) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError)
    }

    class Coordinator: NSObject, QRScannerViewControllerDelegate {
        let onScan: (String) -> Void
        let onError: (ScannerError) -> Void

        init(onScan: @escaping (String) -> Void, onError: @escaping (ScannerError) -> Void) {
            self.onScan = onScan
            self.onError = onError
        }

        func qrScannerDidSuccess(code: String) { onScan(code) }
        func qrScannerDidFail(error: ScannerError) { onError(error) }
    }
}

protocol QRScannerViewControllerDelegate: AnyObject {
    func qrScannerDidSuccess(code: String)
    func qrScannerDidFail(error: ScannerError)
}

/// AVFoundation capture session for QR codes.
///
/// Every configuration failure is reported to the delegate rather than trapped, so a
/// camera problem never terminates the app.
final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    weak var delegate: QRScannerViewControllerDelegate?

    private var didScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    private func configureSession() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            delegate?.qrScannerDidFail(error: .noCameraAvailable)
            return
        }

        let session = AVCaptureSession()

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            delegate?.qrScannerDidFail(error: .configurationFailed(error.localizedDescription))
            return
        }

        guard session.canAddInput(videoInput) else {
            delegate?.qrScannerDidFail(error: .configurationFailed("the capture session rejected the camera input"))
            return
        }
        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            delegate?.qrScannerDidFail(error: .configurationFailed("the capture session rejected the QR output"))
            return
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        self.captureSession = session
        self.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    /// SwiftUI often loads a `UIViewControllerRepresentable` with a 0×0 frame
    /// first. This resizes the camera layer once real dimensions arrive.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didScan,
              let readableObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue
        else { return }

        didScan = true
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        delegate?.qrScannerDidSuccess(code: stringValue)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }
}
