import Foundation

@objc protocol CoreClientProtocol {
    func videoFrameAvailable(width: Int, height: Int, pitch: Int, format: Int)
    func audioSamplesAvailable(count: Int)
    func coreOptionsV1(_ optionsArray: [[String: Any]])
    func coreOptionsV2(_ optionsArray: [[String: Any]], categoriesArray: [[String: Any]])
    func gameLoaded(romPath: String)
    func coreFailed(message: String)
    func geometryChanged(width: Int, height: Int, aspectRatio: Float)
    func rotationChanged(rotation: Int)

    // RetroAchievements (rcheevos) events — fired from the XPC service where the
    // rcheevos runtime lives alongside the libretro core. The main app routes
    // these to RetroAchievementsService.
    func rcheevosAchievementTriggered(id: Int)
    func rcheevosAchievementProgress(id: Int, value: Int)
    func rcheevosChallengeStarted(id: Int)
    func rcheevosChallengeCancelled(id: Int)
    func rcheevosRichPresenceUpdate(message: String)
}
