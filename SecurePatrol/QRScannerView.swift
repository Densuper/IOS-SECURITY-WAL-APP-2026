import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: ScannerController, coordinator: ()) {
        uiViewController.stopScanning()
    }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.densuper.securepatrol.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var delivered = false
    private var visible = false
    // Accessed only on sessionQueue.
    private var configured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        preview = layer
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startScanning()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.visible else { return }
                    if granted {
                        self.startScanning()
                    } else {
                        self.showMessage("Camera access is required to scan QR codes.")
                    }
                }
            }
        default:
            showMessage("Enable camera access in Settings to scan QR codes.")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    private func startScanning() {
        guard visible, !delivered else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    self.reportCameraError("Camera is unavailable.")
                    return
                }
                self.session.beginConfiguration()
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    self.reportCameraError("Camera is unavailable.")
                    return
                }
                self.session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard self.session.canAddOutput(output) else {
                    self.session.removeInput(input)
                    self.session.commitConfiguration()
                    self.reportCameraError("QR scanning is unavailable.")
                    return
                }
                self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                self.session.commitConfiguration()
                self.configured = true
            }
            self.session.startRunning()
        }
    }

    func stopScanning() {
        visible = false
        let captureSession = session
        sessionQueue.async {
            if captureSession.isRunning { captureSession.stopRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard visible, !delivered,
              let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        delivered = true
        stopScanning()
        onCode?(code)
    }

    private func reportCameraError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.visible else { return }
            self.showMessage(message)
        }
    }

    private func showMessage(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }
}
