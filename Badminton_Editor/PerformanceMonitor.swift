import Foundation
import SwiftUI
import os.log

/// Performance monitoring system for timeline scrubbing operations
/// Implements task 15 requirements for frame rate and memory monitoring
@MainActor
class PerformanceMonitor: ObservableObject {
    // MARK: - Published Properties
    
    /// Current frame rate during scrubbing operations
    @Published var currentFrameRate: Double = 60.0
    
    /// Current memory usage in MB
    @Published var memoryUsageMB: Double = 0.0
    
    /// Whether performance is currently being monitored
    @Published var isMonitoring: Bool = false
    
    /// Performance warnings and alerts
    @Published var performanceWarnings: [PerformanceWarning] = []
    
    // MARK: - Private Properties
    
    private var frameRateTimer: Timer?
    private var memoryTimer: Timer?
    private var frameTimestamps: [CFTimeInterval] = []
    private let maxFrameTimestamps = 60 // Track last 60 frames for 1-second average
    
    // Performance thresholds
    private let targetFrameRate: Double = 60.0
    private let minimumAcceptableFrameRate: Double = 30.0
    private let memoryWarningThreshold: Double = 100.0 // MB
    private let memoryCriticalThreshold: Double = 200.0 // MB
    
    // Logging
    private let logger = Logger(subsystem: "BadmintonEditor", category: "Performance")
    
    // MARK: - Performance Warning Types
    
    struct PerformanceWarning: Identifiable, Equatable {
        let id = UUID()
        let type: WarningType
        let message: String
        let timestamp: Date
        let severity: Severity
        
        enum WarningType {
            case lowFrameRate
            case highMemoryUsage
            case criticalMemoryUsage
            case seekFailures
            case cacheOverflow
        }
        
        enum Severity {
            case info
            case warning
            case critical
        }
    }
    
    // MARK: - Initialization
    
    init() {
        setupPerformanceMonitoring()
    }
    
    deinit {
        Task { @MainActor in
            stopMonitoring()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start performance monitoring for timeline scrubbing
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        startFrameRateMonitoring()
        startMemoryMonitoring()
        
        logger.info("Performance monitoring started")
    }
    
    /// Stop performance monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        stopFrameRateMonitoring()
        stopMemoryMonitoring()
        
        logger.info("Performance monitoring stopped")
    }
    
    /// Record a frame timestamp for frame rate calculation
    func recordFrame() {
        guard isMonitoring else { return }
        
        let timestamp = CACurrentMediaTime()
        frameTimestamps.append(timestamp)
        
        // Keep only the most recent timestamps
        if frameTimestamps.count > maxFrameTimestamps {
            frameTimestamps.removeFirst()
        }
        
        // Calculate current frame rate if we have enough samples
        if frameTimestamps.count >= 2 {
            calculateFrameRate()
        }
    }
    
    /// Clear all performance warnings
    func clearWarnings() {
        performanceWarnings.removeAll()
    }
    
    /// Get performance summary for debugging
    func getPerformanceSummary() -> PerformanceSummary {
        return PerformanceSummary(
            frameRate: currentFrameRate,
            memoryUsage: memoryUsageMB,
            warningCount: performanceWarnings.count,
            isMonitoring: isMonitoring
        )
    }
    
    // MARK: - Frame Rate Monitoring
    
    private func startFrameRateMonitoring() {
        frameRateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkFrameRatePerformance()
            }
        }
    }
    
    private func stopFrameRateMonitoring() {
        frameRateTimer?.invalidate()
        frameRateTimer = nil
        frameTimestamps.removeAll()
    }
    
    private func calculateFrameRate() {
        guard frameTimestamps.count >= 2 else { return }
        
        let timeSpan = frameTimestamps.last! - frameTimestamps.first!
        let frameCount = Double(frameTimestamps.count - 1)
        
        if timeSpan > 0 {
            currentFrameRate = frameCount / timeSpan
        }
    }
    
    private func checkFrameRatePerformance() {
        if currentFrameRate < minimumAcceptableFrameRate {
            addPerformanceWarning(
                type: .lowFrameRate,
                message: "Frame rate dropped to \(String(format: "%.1f", currentFrameRate)) fps",
                severity: currentFrameRate < 20 ? .critical : .warning
            )
            
            logger.warning("Low frame rate detected: \(self.currentFrameRate) fps")
        }
    }
    
    // MARK: - Memory Monitoring
    
    private func startMemoryMonitoring() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryUsage()
            }
        }
    }
    
    private func stopMemoryMonitoring() {
        memoryTimer?.invalidate()
        memoryTimer = nil
    }
    
    private func updateMemoryUsage() {
        let memoryInfo = getMemoryUsage()
        memoryUsageMB = memoryInfo.used
        
        checkMemoryThresholds()
    }
    
    private func getMemoryUsage() -> (used: Double, available: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / (1024 * 1024)
            return (used: usedMB, available: 0) // Available memory calculation is complex on iOS
        } else {
            return (used: 0, available: 0)
        }
    }
    
    private func checkMemoryThresholds() {
        if memoryUsageMB > memoryCriticalThreshold {
            addPerformanceWarning(
                type: .criticalMemoryUsage,
                message: "Critical memory usage: \(String(format: "%.1f", memoryUsageMB)) MB",
                severity: .critical
            )
            
            logger.error("Critical memory usage: \(self.memoryUsageMB) MB")
            
            // Trigger automatic cleanup
            NotificationCenter.default.post(
                name: NSNotification.Name("PerformanceMemoryCritical"),
                object: nil,
                userInfo: ["memoryUsage": memoryUsageMB]
            )
            
        } else if memoryUsageMB > memoryWarningThreshold {
            addPerformanceWarning(
                type: .highMemoryUsage,
                message: "High memory usage: \(String(format: "%.1f", memoryUsageMB)) MB",
                severity: .warning
            )
            
            logger.warning("High memory usage: \(self.memoryUsageMB) MB")
        }
    }
    
    // MARK: - Warning Management
    
    private func addPerformanceWarning(type: PerformanceWarning.WarningType, message: String, severity: PerformanceWarning.Severity) {
        let warning = PerformanceWarning(
            type: type,
            message: message,
            timestamp: Date(),
            severity: severity
        )
        
        // Avoid duplicate warnings of the same type within a short time
        let recentWarnings = performanceWarnings.filter { 
            $0.type == type && Date().timeIntervalSince($0.timestamp) < 5.0 
        }
        
        if recentWarnings.isEmpty {
            performanceWarnings.append(warning)
            
            // Keep only the most recent warnings
            if performanceWarnings.count > 10 {
                performanceWarnings.removeFirst()
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupPerformanceMonitoring() {
        // Setup memory warning notifications
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSystemMemoryWarning()
            }
        }
    }
    
    private func handleSystemMemoryWarning() {
        addPerformanceWarning(
            type: .criticalMemoryUsage,
            message: "System memory warning received",
            severity: .critical
        )
        
        logger.error("System memory warning received")
        
        // Post notification for automatic cleanup
        NotificationCenter.default.post(
            name: NSNotification.Name("PerformanceMemoryCritical"),
            object: nil,
            userInfo: ["systemWarning": true]
        )
    }
}

// MARK: - Performance Summary

struct PerformanceSummary {
    let frameRate: Double
    let memoryUsage: Double
    let warningCount: Int
    let isMonitoring: Bool
    
    var isPerformanceGood: Bool {
        return frameRate >= 30.0 && memoryUsage < 100.0 && warningCount == 0
    }
    
    var statusDescription: String {
        if isPerformanceGood {
            return "Performance: Good"
        } else if frameRate < 30.0 {
            return "Performance: Low Frame Rate"
        } else if memoryUsage > 100.0 {
            return "Performance: High Memory Usage"
        } else {
            return "Performance: Issues Detected"
        }
    }
}

// MARK: - Performance Extensions

extension PerformanceMonitor {
    /// Record seek operation performance
    func recordSeekOperation(duration: TimeInterval, success: Bool) {
        if !success {
            addPerformanceWarning(
                type: .seekFailures,
                message: "Seek operation failed (duration: \(String(format: "%.3f", duration))s)",
                severity: .warning
            )
        }
        
        if duration > 0.1 { // Seek took longer than 100ms
            addPerformanceWarning(
                type: .seekFailures,
                message: "Slow seek operation: \(String(format: "%.3f", duration))s",
                severity: .info
            )
        }
    }
    
    /// Record cache operation performance
    func recordCacheOperation(type: String, itemCount: Int, duration: TimeInterval) {
        if duration > 1.0 { // Cache operation took longer than 1 second
            addPerformanceWarning(
                type: .cacheOverflow,
                message: "\(type) operation slow: \(itemCount) items in \(String(format: "%.3f", duration))s",
                severity: .info
            )
        }
    }
}