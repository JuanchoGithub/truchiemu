import Foundation
import Combine

// Shared state for tracking game drag operations across views
@MainActor
class GameDragState: ObservableObject {
    static let shared = GameDragState()
    
    // Currently dragged game IDs
    @Published var draggedGameIDs: [UUID] = []
    
    // Whether a drag operation is in progress
    @Published var isDraggingGames: Bool = false
    
    private init() {}
    
    func startDrag(gameIDs: [UUID]) {
        draggedGameIDs = gameIDs
        isDraggingGames = true
    }
    
    func endDrag() {
        draggedGameIDs = []
        isDraggingGames = false
    }
}