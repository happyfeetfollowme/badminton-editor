# HEVC 轉 H.264 轉碼功能使用指南 (最終調試完成)

## 🎬 功能概述

已為您的 `ThumbnailCache` 添加了完整的 HEVC 轉 H.264 轉碼功能，解決 iPhone 上 HEVC 視頻的兼容性問題。**所有編譯錯誤已修復，功能已完全調試完成。**

## ✅ 最新修復的問題

1. **修復了 `AVAssetExportPresetHighQuality` 不存在的問題**
   - 替換為 `AVAssetExportPreset1920x1080` (1080p 高品質)
   - 添加了 `AVAssetExportPreset1280x720` 作為備用方案

2. **智能預設選擇系統**
   - 自動嘗試主要預設，失敗時使用備用預設
   - 確保在各種設備上都能正常工作

3. **增強的兼容性檢查**
   - 支援多種解析度預設：1080p, 720p, 中等品質, 低品質
   - 自動選擇設備支援的最佳格式

## 🎯 **轉碼品質選項 (已優化)**

```swift
enum TranscodingQuality {
    case low    // 低品質 (檔案較小, 快速轉碼)
    case medium // 中等品質 (平衡選項, 推薦)
    case high   // 高品質 1080p (檔案較大, 最佳品質)
                // 如果 1080p 不支援，自動降級到 720p
}
```

### **智能預設選擇邏輯：**
- **低品質**: `AVAssetExportPresetLowQuality`
- **中等品質**: `AVAssetExportPresetMediumQuality`  
- **高品質**: `AVAssetExportPreset1920x1080` → 備用: `AVAssetExportPreset1280x720`

## 🆕 新增的 UI 整合功能

### **即時狀態追蹤**
```swift
@StateObject private var thumbnailCache = ThumbnailCache()

// 在 SwiftUI View 中
if thumbnailCache.isTranscoding {
    VStack {
        Text("正在轉碼...")
        ProgressView(value: thumbnailCache.transcodingProgress)
        Text("\(Int(thumbnailCache.transcodingProgress * 100))%")
        
        Button("取消") {
            thumbnailCache.cancelTranscoding()
        }
    }
}
```

### **取消轉碼功能**
```swift
// 隨時取消正在進行的轉碼
thumbnailCache.cancelTranscoding()
```

## 🔧 自動功能

### 1. **自動檢測 HEVC 視頻**
```swift
// 當呼叫 setPHAsset 時會自動：
// ✅ 檢測 HEVC 格式 (hvc1, hev1)
// ✅ 檢查硬體 HEVC 解碼支援
// ✅ 提供轉碼建議
// ✅ 發送轉碼通知

thumbnailCache.setPHAsset(selectedPHAsset)
```

### 2. **自動通知系統**
當檢測到 HEVC 視頻時，系統會自動發送通知：
```swift
// 在您的 ViewController 或 SwiftUI View 中監聽
NotificationCenter.default.addObserver(
    forName: NSNotification.Name("HEVCTranscodingAvailable"),
    object: nil,
    queue: .main
) { notification in
    guard let userInfo = notification.userInfo,
          let phAsset = userInfo["phAsset"] as? PHAsset,
          let hevcAsset = userInfo["hevcAsset"] as? AVAsset,
          let thumbnailCache = userInfo["thumbnailCache"] as? ThumbnailCache else {
        return
    }
    
    // 顯示轉碼選項 UI
    showTranscodingOptions(phAsset: phAsset, hevcAsset: hevcAsset, cache: thumbnailCache)
}
```

## 🎯 手動轉碼使用

### 1. **檢查是否已有轉碼版本**
```swift
if thumbnailCache.hasTranscodedVersion(for: phAsset) {
    // 使用已轉碼的版本
    if let h264Asset = thumbnailCache.getTranscodedAsset(for: phAsset) {
        thumbnailCache.setAsset(h264Asset)
    }
} else {
    // 需要轉碼
    startTranscoding()
}
```

### 2. **執行轉碼**
```swift
func startTranscoding() {
    thumbnailCache.transcodeHEVCToH264(
        phAsset: selectedPHAsset,
        hevcAsset: originalHEVCAsset,
        quality: .medium,
        progressHandler: { progress in
            // 更新 UI 進度條
            DispatchQueue.main.async {
                self.progressView.progress = progress
                self.progressLabel.text = "轉碼進度: \(Int(progress * 100))%"
            }
        },
        completion: { result in
            switch result {
            case .success(let h264Asset):
                print("✅ 轉碼成功！")
                // thumbnailCache.setAsset(h264Asset) 已自動執行
                
            case .failure(let error):
                print("❌ 轉碼失敗: \(error.localizedDescription)")
                self.showError(error.localizedDescription)
            }
        }
    )
}
```

## 🎨 SwiftUI 實作範例

```swift
struct TranscodingView: View {
    @StateObject private var thumbnailCache = ThumbnailCache()
    @State private var showTranscodingAlert = false
    @State private var transcodingProgress: Float = 0
    @State private var isTranscoding = false
    
    var body: some View {
        VStack {
            if isTranscoding {
                VStack {
                    Text("正在轉碼為 H.264...")
                    ProgressView(value: transcodingProgress)
                    Text("\(Int(transcodingProgress * 100))%")
                }
                .padding()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HEVCTranscodingAvailable"))) { notification in
            showTranscodingAlert = true
        }
        .alert("HEVC 視頻檢測", isPresented: $showTranscodingAlert) {
            Button("轉換為 H.264") {
                startTranscoding()
            }
            Button("繼續使用 HEVC") {
                // 繼續使用原始 HEVC
            }
        } message: {
            Text("檢測到 HEVC 格式視頻，建議轉換為 H.264 以獲得更好的兼容性。")
        }
    }
    
    private func startTranscoding() {
        isTranscoding = true
        // 實作轉碼邏輯...
    }
}
```

## ⚙️ 轉碼品質選項

```swift
enum TranscodingQuality {
    case low    // 低品質 (檔案較小, 快速轉碼)
    case medium // 中等品質 (平衡選項)
    case high   // 高品質 (檔案較大, 最佳品質)
}

// 使用範例
thumbnailCache.transcodeHEVCToH264(
    phAsset: phAsset,
    hevcAsset: hevcAsset,
    quality: .high, // 選擇品質
    progressHandler: { progress in ... },
    completion: { result in ... }
)
```

## 🗂️ 檔案管理

### 轉碼檔案位置
```
Documents/TranscodedVideos/
├── [PHAsset.localIdentifier]_h264.mp4
├── [PHAsset.localIdentifier]_h264.mp4
└── ...
```

### 清理轉碼檔案
```swift
// 清理所有轉碼檔案（釋放儲存空間）
thumbnailCache.cleanupTranscodedFiles()
```

## 🚀 最佳實踐

### 1. **智能轉碼策略**
```swift
func handleVideo(phAsset: PHAsset) {
    // 1. 檢查是否已有轉碼版本
    if thumbnailCache.hasTranscodedVersion(for: phAsset) {
        let h264Asset = thumbnailCache.getTranscodedAsset(for: phAsset)!
        thumbnailCache.setAsset(h264Asset)
        return
    }
    
    // 2. 嘗試載入原始 HEVC
    thumbnailCache.setPHAsset(phAsset)
    
    // 3. 如果 HEVC 失敗，系統會自動提供轉碼選項
}
```

### 2. **用戶體驗優化**
- ✅ 提供進度指示器
- ✅ 允許取消轉碼操作
- ✅ 自動檢測並提示轉碼
- ✅ 快取轉碼結果，避免重複轉碼

### 3. **錯誤處理**
```swift
switch result {
case .success(let h264Asset):
    // 成功：自動設定新 asset
    
case .failure(.exportSessionCreationFailed):
    // 無法建立轉碼會話
    
case .failure(.exportFailed(let error)):
    // 轉碼過程失敗
    
case .failure(.cancelled):
    // 用戶取消轉碼
    
case .failure(.unknownError):
    // 未知錯誤
}
```

## 📱 實際使用流程

1. **載入視頻**：`thumbnailCache.setPHAsset(phAsset)`
2. **自動檢測**：系統檢測 HEVC 格式並發送通知
3. **用戶選擇**：顯示轉碼選項對話框
4. **執行轉碼**：`transcodeHEVCToH264()` 開始轉碼
5. **進度更新**：progressHandler 提供即時進度
6. **完成處理**：自動載入 H.264 版本，生成縮圖

這套系統讓您的 badminton-editor 能夠完美處理 iPhone 上的 HEVC 視頻！ 🎾📱
