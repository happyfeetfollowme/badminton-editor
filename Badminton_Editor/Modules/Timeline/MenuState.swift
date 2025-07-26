import SwiftUI
import Foundation

/// ObservableObject for managing context menu visibility and positioning
class MenuState: ObservableObject {
    // MARK: - Published Properties
    
    /// Controls whether the context menu is currently visible
    @Published var isVisible: Bool = false
    
    /// The position where the menu should be displayed
    @Published var position: CGPoint = .zero
    
    /// The ID of the clip that the menu is targeting
    @Published var targetClipId: UUID? = nil
    
    // MARK: - Public Methods
    
    /// Shows the context menu at the specified position for the given clip
    /// - Parameters:
    ///   - position: The CGPoint where the menu should appear
    ///   - clipId: The UUID of the clip the menu is associated with
    func showMenu(at position: CGPoint, for clipId: UUID) {
        self.position = position
        self.targetClipId = clipId
        self.isVisible = true
    }
    
    /// Hides the context menu and clears associated state
    func hideMenu() {
        self.isVisible = false
        self.targetClipId = nil
        self.position = .zero
    }
    
    /// Calculates the menu position relative to the timeline center
    /// - Parameters:
    ///   - timelineCenter: The center x-coordinate of the timeline view
    ///   - thumbnailViewTop: The top y-coordinate of the thumbnail view
    ///   - menuHeight: The height of the menu to position above thumbnails
    /// - Returns: The calculated position for the menu
    func calculateMenuPosition(timelineCenter: CGFloat, thumbnailViewTop: CGFloat, menuHeight: CGFloat) -> CGPoint {
        let menuX = timelineCenter
        let menuY = thumbnailViewTop - menuHeight - 8 // 8 points padding above thumbnails
        
        return CGPoint(x: menuX, y: menuY)
    }
}