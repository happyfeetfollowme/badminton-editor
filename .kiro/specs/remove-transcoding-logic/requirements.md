# Requirements Document

## Introduction

由於現在可以直接使用 PhotosUI framework 讀取不同格式的影片，包括 HEVC 格式，因此不再需要轉碼相關的邏輯。本功能將移除所有轉碼相關的代碼，但保留 GPU 優化的邏輯以確保視頻播放性能。

## Requirements

### Requirement 1

**User Story:** 作為開發者，我希望移除不必要的轉碼邏輯，以簡化代碼庫並減少維護負擔。

#### Acceptance Criteria

1. WHEN 系統檢測到 HEVC 視頻 THEN 系統 SHALL 直接使用原始格式而不提供轉碼選項
2. WHEN 用戶選擇視頻 THEN 系統 SHALL 直接載入視頻而不進行格式檢查和轉碼提示
3. WHEN 系統處理視頻 THEN 系統 SHALL 移除所有轉碼相關的 UI 元素和進度指示器

### Requirement 2

**User Story:** 作為用戶，我希望系統能夠直接播放各種格式的視頻，包括 HEVC，而不需要等待轉碼過程。

#### Acceptance Criteria

1. WHEN 用戶選擇 HEVC 視頻 THEN 系統 SHALL 直接載入並播放視頻
2. WHEN 用戶選擇 H.264 視頻 THEN 系統 SHALL 直接載入並播放視頻
3. WHEN 系統載入視頻 THEN 系統 SHALL 不顯示轉碼相關的對話框或進度條

### Requirement 3

**User Story:** 作為開發者，我希望保留 GPU 優化邏輯，以確保視頻播放的性能和流暢度。

#### Acceptance Criteria

1. WHEN 系統載入視頻 THEN 系統 SHALL 保留硬體解碼加速設置
2. WHEN 系統配置播放器 THEN 系統 SHALL 保留 GPU 相關的優化設置
3. WHEN 系統處理不同解析度視頻 THEN 系統 SHALL 保留解析度相關的性能優化

### Requirement 4

**User Story:** 作為開發者，我希望清理所有轉碼相關的文件和代碼，以保持代碼庫的整潔。

#### Acceptance Criteria

1. WHEN 清理代碼 THEN 系統 SHALL 移除轉碼相關的方法和屬性
2. WHEN 清理代碼 THEN 系統 SHALL 移除轉碼相關的通知和回調
3. WHEN 清理代碼 THEN 系統 SHALL 移除轉碼相關的文檔和範例文件

### Requirement 5

**User Story:** 作為用戶，我希望視頻載入過程更加快速和簡潔，不被不必要的轉碼檢查拖慢。

#### Acceptance Criteria

1. WHEN 用戶選擇視頻 THEN 系統 SHALL 跳過 HEVC 格式檢測邏輯
2. WHEN 系統載入視頻 THEN 系統 SHALL 不執行轉碼可行性檢查
3. WHEN 系統處理視頻 THEN 系統 SHALL 直接進入 GPU 優化配置階段