import Combine
import Foundation

/// The progress of the RetroAchievements library match.
///
/// The progress lives in its own object. The library window observes the
/// RetroAchievements service. A progress change in the service redraws the
/// whole library window. That took 25 seconds for one library match.
@MainActor
final class RAMatchProgress: ObservableObject {
    static let shared = RAMatchProgress()

    @Published var isMatchingAll = false
    @Published var matchedAllCount = 0
    @Published var matchedAllTotal = 0

    // True during the cache-import phase of "Match All Games". When true the
    // views show "Importing game cache (step/total files)"; when false they
    // show the matched-count progress line.
    @Published var isImportingRACache = false
    @Published var importRACacheStep = 0
    @Published var importRACacheTotal = 0

    // The ROM that the match phase checks now.
    @Published var currentRomName = ""
    // The number of checked ROMs.
    @Published var step = 0
    // The number of ROMs to check.
    @Published var total = 0

    private init() {}

    /// The text of the progress line. The view shows the text.
    var statusLine: String {
        let format = LocalizationManager.shared.localized("retroAchievements.verifyingRomProgress")
        let truncated = String(currentRomName.prefix(25))
        return format
            .replacingOccurrences(of: "{0}", with: truncated)
            .replacingOccurrences(of: "{1}", with: "\(step)")
            .replacingOccurrences(of: "{2}", with: "\(total)")
    }
}
