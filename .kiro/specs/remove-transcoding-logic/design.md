# Design Document

## Overview

本設計文檔描述如何移除 Badminton Editor 中的轉碼相關邏輯，同時保留 GPU 優化功能。由於 PhotosUI framework 現在可以直接處理各種視頻格式（包括 HEVC），轉碼功能已變得不必要，移除這些代碼將簡化系統架構並提升性能。

## Architecture

### 當前架構分析

當前系統包含以下轉碼相關組件：

1. **ThumbnailCache.swift** - 包含完整的轉碼邏輯
2. **ContentView.swift** - 包含轉碼進度 UI 和相關狀態管理
3. **TranscodingExampleView.swift** - 轉碼功能的示例實現
4. **HEVC_Transcoding_Guide.md** - 轉碼功能文檔

### 目標架構

移除轉碼後的簡化架構：

1. **ThumbnailCache.swift** - 僅保留縮圖生成和 GPU 優化邏輯
2. **ContentView.swift** - 移除轉碼 UI，保留視頻載入和 GPU 優化
3. **移除不必要的文件** - 刪除轉碼相關的示例和文檔

## Components and Interfaces

### 需要修改的組件

#### 1. ThumbnailCache.swift

**移除的功能：**
- 轉碼相關的屬性和方法
- HEVC 檢測和轉碼提示邏輯
- 轉碼進度追蹤
- 轉碼文件管理

**保留的功能：**
- GPU 硬體解碼支援檢查
- 視頻載入和縮圖生成
- 性能優化設置

**具體修改：**
```swift
// 移除這些屬性
@Published var isTranscoding: Bool = false
@Published var transcodingProgress: Float = 0.0
private var activeExportSession: AVAssetExportSession?

// 移除這些方法
func transcodeHEVCToH264(...)
func offerTranscodingOption(...)
func canTranscodeToH264(...)
func hasTranscodedVersion(...)
func getTranscodedAsset(...)
func cleanupTranscodedFiles()
func cancelTranscoding()

// 簡化 setPHAsset 方法，移除 HEVC 檢測和轉碼提示
```

#### 2. ContentView.swift

**移除的功能：**
- TranscodingProgressPopup UI 組件
- 轉碼相關的狀態變數
- 轉碼進度顯示邏輯

**保留的功能：**
- 所有 GPU 優化相關的方法
- 視頻載入和播放邏輯
- 性能監控

**具體修改：**
```swift
// 移除轉碼進度彈窗
// if thumbnailCache.isTranscoding || showLoadingAnimation {
//     TranscodingProgressPopup(...)
// }

// 簡化載入動畫邏輯，僅保留基本載入指示
if showLoadingAnimation {
    BasicLoadingIndicator(...)
}

// 保留所有 GPU 相關方法：
// - applyInstantGPUOptimizations
// - configureDetailedGPUAcceleration
// - configureUniversalGPUAcceleration
// - checkUniversalGPUSupport
```

#### 3. 文件清理

**需要刪除的文件：**
- `TranscodingExampleView.swift`
- `HEVC_Transcoding_Guide.md`

### GPU 優化邏輯保留策略

#### 保留的 GPU 相關功能

1. **硬體解碼檢查**
```swift
// 保留 VTIsHardwareDecodeSupported 檢查
let hevcSupported = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
let h264Supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)
```

2. **播放器優化設置**
```swift
// 保留所有 AVPlayerItem 優化設置
playerItem.preferredMaximumResolution = CGSize(width: 3840, height: 2160)
playerItem.preferredPeakBitRate = codecInfo.isHEVC ? 50_000_000 : 80_000_000
playerItem.preferredForwardBufferDuration = 2.5
```

3. **編碼格式檢測**
```swift
// 保留編碼格式檢測，但僅用於 GPU 優化
private func detectVideoCodecFormat(_ asset: AVAsset) async -> VideoCodecInfo
```

## Data Models

### 移除的數據模型

```swift
// 移除轉碼相關的枚舉和錯誤類型
enum TranscodingQuality { ... }
enum TranscodingError { ... }
```

### 保留的數據模型

```swift
// 保留視頻編碼信息結構，用於 GPU 優化
struct VideoCodecInfo {
    let codecName: String
    let isHEVC: Bool
    let fourCC: FourCharCode
}
```

## Error Handling

### 簡化的錯誤處理

移除轉碼相關的錯誤處理邏輯，簡化為：

1. **視頻載入錯誤** - 直接顯示載入失敗訊息
2. **GPU 優化錯誤** - 降級到基本播放設置
3. **縮圖生成錯誤** - 使用預設縮圖或重試機制

### 錯誤處理流程

```swift
// 簡化的錯誤處理
private func handleVideoLoadError(_ error: Error) {
    print("Video load failed: \(error)")
    // 直接顯示錯誤，不提供轉碼選項
    showErrorMessage("無法載入視頻文件")
}
```

## Testing Strategy

### 測試重點

1. **功能移除驗證**
   - 確認所有轉碼相關代碼已完全移除
   - 驗證不再顯示轉碼相關 UI
   - 確認 HEVC 視頻可以直接播放

2. **GPU 優化保留驗證**
   - 測試各種視頻格式的 GPU 優化是否正常工作
   - 驗證硬體解碼加速功能
   - 確認性能優化設置正確應用

3. **回歸測試**
   - 測試視頻載入和播放功能
   - 驗證縮圖生成功能
   - 確認 UI 響應性和用戶體驗

### 測試用例

1. **HEVC 視頻直接播放測試**
   - 選擇 HEVC 格式視頻
   - 驗證直接載入播放，無轉碼提示
   - 確認 GPU 優化正常應用

2. **H.264 視頻播放測試**
   - 選擇 H.264 格式視頻
   - 驗證正常載入和播放
   - 確認性能優化設置

3. **UI 清理驗證**
   - 確認不再顯示轉碼進度條
   - 驗證不再有轉碼相關按鈕或對話框
   - 確認載入動畫簡化且快速

## Performance Considerations

### 性能提升預期

1. **載入速度提升**
   - 移除 HEVC 檢測邏輯，減少載入時間
   - 直接進入 GPU 優化階段
   - 簡化 UI 更新邏輯

2. **記憶體使用優化**
   - 移除轉碼相關的狀態管理
   - 減少不必要的通知和回調
   - 簡化對象生命週期

3. **代碼維護性**
   - 減少代碼複雜度
   - 移除不必要的依賴
   - 簡化錯誤處理邏輯

### GPU 優化保留的重要性

保留 GPU 優化邏輯確保：
- 各種格式視頻的最佳播放性能
- 硬體解碼加速的正確應用
- 不同解析度視頻的適當處理