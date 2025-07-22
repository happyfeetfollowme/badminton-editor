import AVFoundation
import VideoToolbox
import UIKit
import Photos

// MARK: - VideoCodecInfo
struct VideoCodecInfo {
    let codecName: String
    let isHEVC: Bool
    let fourCC: FourCharCode
}

// MARK: - Video Utility Functions

func detectVideoCodecFormat(_ asset: AVAsset) async -> VideoCodecInfo {
    do {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let firstTrack = tracks.first else {
            return VideoCodecInfo(codecName: "Unknown", isHEVC: false, fourCC: 0)
        }
        let formatDescriptions = try await firstTrack.load(.formatDescriptions)
        guard let firstFormat = formatDescriptions.first else {
            return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: 0)
        }
        let formatDescription = firstFormat as! CMFormatDescription
        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
        return identifyCodecFast(mediaSubType)
    } catch {
        return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: 0)
    }
}

func identifyCodecFast(_ fourCC: FourCharCode) -> VideoCodecInfo {
    switch fourCC {
    case 0x68766331, 0x68657631, kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha:
        return VideoCodecInfo(codecName: "HEVC/H.265", isHEVC: true, fourCC: fourCC)
    case 0x61766331, 0x61766343, kCMVideoCodecType_H264:
        return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: fourCC)
    default:
        return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: fourCC)
    }
}

func checkAssetAvailability(_ asset: AVAsset) async -> Bool {
    do {
        if #available(iOS 16.0, *) {
            let duration = try await asset.load(.duration)
            if duration.seconds > 0 && duration.seconds.isFinite {
                return true
            }
        } else {
            let duration = asset.duration
            if duration.seconds > 0 && duration.seconds.isFinite {
                return true
            }
        }
    } catch {}
    do {
        if #available(iOS 16.0, *) {
            let tracks = try await asset.load(.tracks)
            let videoTracks = tracks.filter { $0.mediaType == .video }
            if !videoTracks.isEmpty {
                return true
            }
        } else {
            let videoTracks = asset.tracks(withMediaType: .video)
            if !videoTracks.isEmpty {
                return true
            }
        }
    } catch {}
    if asset.debugDescription.contains("AVURLAsset") {
        return true
    }
    return false
}

func configureAudioSession() async {
    do {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowBluetooth, .allowAirPlay])
        try audioSession.setPreferredSampleRate(44100)
        try audioSession.setPreferredIOBufferDuration(0.01)
        try audioSession.setActive(true)
    } catch {}
}

func formatTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    return String(format: "%02d:%02d", minutes, seconds)
}
