import AVFoundation
import HaishinKit
import Photos
import UIKit
import VideoToolbox

final class LiveViewController: UIViewController {
    private var rtmpConnection = RTMPConnection()
    private var rtmpStream: RTMPStream!
    private var currentPosition: AVCaptureDevice.Position = .back
    private var videoBitRate = VideoCodecSettings.default.bitRate

    override func viewDidLoad() {
        super.viewDidLoad()

        rtmpConnection.delegate = self

        rtmpStream = RTMPStream(connection: rtmpConnection)
        if let orientation = DeviceUtil.videoOrientation(by: UIApplication.shared.statusBarOrientation) {
            rtmpStream.videoOrientation = orientation
        }

        rtmpStream.loopback = DeviceUtil.isHeadphoneConnected()

        rtmpStream.audioSettings = AudioCodecSettings(
            bitRate: 64 * 1000
        )

        rtmpStream.videoSettings = VideoCodecSettings(
            videoSize: .init(width: 854, height: 480),
            profileLevel: kVTProfileLevel_H264_Baseline_3_1 as String,
            bitRate: 640 * 1000,
            maxKeyFrameIntervalDuration: 2,
            scalingMode: .trim,
            bitRateMode: .average,
            allowFrameReordering: nil,
            isHardwareEncoderEnabled: true
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition)

        // If you're using multi-camera functionality, please make sure to call the attachMultiCamera method first. This is required for iOS 14 and 15, among others.
        if #available(iOS 13.0, *) {
            let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            rtmpStream.videoCapture(for: 1)?.isVideoMirrored = true
            rtmpStream.attachMultiCamera(front)
        }
        rtmpStream.attachCamera(back) { error in
            logger.warn(error)
        }
        rtmpStream.attachAudio(AVCaptureDevice.default(for: .audio), automaticallyConfiguresApplicationAudioSession: false) { error in
            logger.warn(error)
        }
        rtmpStream.addObserver(self, forKeyPath: "currentFPS", options: .new, context: nil)
        (view as? NetStreamDrawable)?.attachStream(rtmpStream)
    }

    override func viewWillDisappear(_ animated: Bool) {
        logger.info("viewWillDisappear")
        super.viewWillDisappear(animated)
        rtmpStream.removeObserver(self, forKeyPath: "currentFPS")
        rtmpStream.close()
        rtmpStream.attachAudio(nil)
        rtmpStream.attachCamera(nil)
        if #available(iOS 13.0, *) {
            rtmpStream.attachMultiCamera(nil)
        }
    }

    @IBAction func rotateCamera(_ sender: UIButton) {
        logger.info("rotateCamera")
        let position: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        rtmpStream.videoCapture(for: 0)?.isVideoMirrored = position == .front
        rtmpStream.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)) { error in
            logger.warn(error)
        }
        if #available(iOS 13.0, *) {
            rtmpStream.videoCapture(for: 1)?.isVideoMirrored = currentPosition == .front
            rtmpStream.attachMultiCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition)) { error in
                logger.warn(error)
            }
        }
        currentPosition = position
    }
}

extension LiveViewController: RTMPConnectionDelegate {
    func connection(_ connection: RTMPConnection, publishInsufficientBWOccured stream: RTMPStream) {
        // Adaptive bitrate streaming exsample. Please feedback me your good algorithm. :D
        videoBitRate -= 32 * 1000
        stream.videoSettings.bitRate = max(videoBitRate, 64 * 1000)
    }

    func connection(_ connection: RTMPConnection, publishSufficientBWOccured stream: RTMPStream) {
        videoBitRate += 32 * 1000
        stream.videoSettings.bitRate = min(videoBitRate, VideoCodecSettings.default.bitRate)
    }

    func connection(_ connection: RTMPConnection, updateStats stream: RTMPStream) {
    }

    func connection(_ connection: RTMPConnection, didClear stream: RTMPStream) {
        videoBitRate = VideoCodecSettings.default.bitRate
    }
}
