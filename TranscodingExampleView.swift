import SwiftUI
import Photos
import AVFoundation

struct TranscodingExampleView: View {
    @StateObject private var thumbnailCache = ThumbnailCache()
    @State private var selectedPHAsset: PHAsset?
    @State private var showTranscodingAlert = false
    @State private var currentHEVCAsset: AVAsset?
    @State private var transcodingQuality: TranscodingQuality = .medium
    
    var body: some View {
        VStack(spacing: 20) {
            Text("HEVC 轉碼示例")
                .font(.title)
                .fontWeight(.bold)
            
            // 轉碼狀態顯示
            if thumbnailCache.isTranscoding {
                VStack {
                    Text("正在轉碼為 H.264...")
                        .font(.headline)
                    
                    ProgressView(value: thumbnailCache.transcodingProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("\(Int(thumbnailCache.transcodingProgress * 100))%")
                        .font(.caption)
                    
                    Button("取消轉碼") {
                        thumbnailCache.cancelTranscoding()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }
            
            // 視頻選擇按鈕
            Button("選擇視頻") {
                // 這裡會打開照片庫選擇器
                // 實際實作需要使用 PHPickerViewController
                selectVideo()
            }
            .buttonStyle(.borderedProminent)
            
            // 清理按鈕
            Button("清理轉碼檔案") {
                thumbnailCache.cleanupTranscodedFiles()
            }
            .buttonStyle(.bordered)
            .foregroundColor(.orange)
            
            Spacer()
        }
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HEVCTranscodingAvailable"))) { notification in
            handleHEVCDetected(notification)
        }
        .alert("HEVC 視頻檢測", isPresented: $showTranscodingAlert) {
            VStack {
                Button("高品質轉換") {
                    startTranscoding(quality: .high)
                }
                Button("中等品質轉換 (推薦)") {
                    startTranscoding(quality: .medium)
                }
                Button("低品質轉換 (快速)") {
                    startTranscoding(quality: .low)
                }
                Button("繼續使用 HEVC") {
                    // 不轉碼，繼續使用原始格式
                }
            }
        } message: {
            Text("檢測到 HEVC 格式視頻。建議轉換為 H.264 以獲得更好的兼容性和效能。")
        }
    }
    
    private func selectVideo() {
        // 模擬選擇了一個 PHAsset
        // 實際實作需要使用 PHPickerViewController 或 UIImagePickerController
        
        // 這裡只是示例，實際要從照片庫選擇
        print("開啟照片庫選擇器...")
        
        // 假設用戶選擇了一個視頻
        // selectedPHAsset = chosenAsset
        // thumbnailCache.setPHAsset(selectedPHAsset!)
    }
    
    private func handleHEVCDetected(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let phAsset = userInfo["phAsset"] as? PHAsset,
              let hevcAsset = userInfo["hevcAsset"] as? AVAsset else {
            return
        }
        
        selectedPHAsset = phAsset
        currentHEVCAsset = hevcAsset
        showTranscodingAlert = true
    }
    
    private func startTranscoding(quality: TranscodingQuality) {
        guard let phAsset = selectedPHAsset,
              let hevcAsset = currentHEVCAsset else {
            return
        }
        
        thumbnailCache.transcodeHEVCToH264(
            phAsset: phAsset,
            hevcAsset: hevcAsset,
            quality: quality,
            progressHandler: { progress in
                // 進度會自動更新 UI (因為使用了 @Published)
                print("轉碼進度: \(Int(progress * 100))%")
            },
            completion: { result in
                switch result {
                case .success(let h264Asset):
                    print("✅ 轉碼成功！")
                    print("H.264 asset duration: \(h264Asset.duration.seconds)")
                    
                    // 顯示成功訊息
                    DispatchQueue.main.async {
                        // 可以顯示成功 toast 或更新 UI
                    }
                    
                case .failure(let error):
                    print("❌ 轉碼失敗: \(error.localizedDescription)")
                    
                    // 顯示錯誤訊息
                    DispatchQueue.main.async {
                        // 可以顯示錯誤 alert
                    }
                }
            }
        )
    }
}

// MARK: - 預覽
struct TranscodingExampleView_Previews: PreviewProvider {
    static var previews: some View {
        TranscodingExampleView()
    }
}

// MARK: - 幫助擴展
extension TranscodingQuality {
    var emoji: String {
        switch self {
        case .low: return "🏃‍♂️"
        case .medium: return "⚖️"
        case .high: return "🎯"
        }
    }
    
    var fullDescription: String {
        return "\(emoji) \(description)"
    }
}
