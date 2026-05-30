import SwiftUI

// MARK: - RetroAchievements Settings View
struct RetroAchievementsSettingsView: View {
    static let searchKeywords = "retro achievements hardcore"

    @ObservedObject private var raService = RetroAchievementsService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var raCacheCoordinator = RAGameCacheCoordinator.shared
    @EnvironmentObject private var library: ROMLibrary
    @Environment(\.colorScheme) private var colorScheme
    @State private var username = ""
    @State private var webApiKey = ""
    @State private var password = ""
    @State private var loginError: String?
    @State private var isLoggingIn = false
    @State private var showApiKey = false
    @State private var cacheRefreshError: String?
    @State private var isCacheRefreshing = false
    @State private var matchingStatus: String?
    @State private var isMatching = false
    
    @Binding var searchText: String
    let system: SystemInfo?

    init(searchText: Binding<String> = .constant(""), system: SystemInfo? = nil) {
        self._searchText = searchText
        self.system = system
    }
    
    private var isSearching: Bool {
        !searchText.isEmpty
    }
    
    private func matchesSearch(_ text: String) -> Bool {
        text.fuzzyMatch(searchText)
    }
    
    private func highlightText(_ text: String) -> String {
        return text
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Enable/Disable Section
                if !isSearching || matchesSearch("RetroAchievements enable disable") {
                    enableDisableSection
                }
                
                // Account Section
                if !isSearching || matchesSearch("account username login logout connect api key") {
                    accountSection
                }

                // Cache Section
                if !isSearching || matchesSearch("refresh cache systems games data") {
                    cacheSection
                }

                // Hardcore Mode Section
                if !isSearching || matchesSearch("hardcore mode") {
                    hardcoreModeSection
                }
                
                // Rich Presence Section
                if !isSearching || matchesSearch("rich presence game active") {
                    richPresenceSection
                }
                
                // Info Section
                if !isSearching || matchesSearch("about info") {
                    infoSection
                }
                
                // No results message
                if isSearching && !hasAnyResults {
                    noResultsMessage
                }
        }
        .padding(AppSpacing.xl)
    }
    .navigationTitle(loc.localized("retroAchievements.title"))
    }
    
    private var hasAnyResults: Bool {
        matchesSearch("RetroAchievements enable disable") ||
        matchesSearch("account username login logout connect api key") ||
        matchesSearch("refresh cache systems games data") ||
        matchesSearch("hardcore mode") ||
        matchesSearch("rich presence game active") ||
        matchesSearch("about info")
    }
    
    private var noResultsMessage: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(AppColors.textMuted(colorScheme))
            Text(loc.localized("retroAchievements.noResults"))
                .font(.headline)
            Text(loc.localized("retroAchievements.tryAdjustingSearch"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Section Views
    
    @ViewBuilder
    private var enableDisableSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                if isSearching {
                    Text(loc.localized("retroAchievements.title"))
                        .font(.headline)
                } else {
                    Label { Text(loc.localized("retroAchievements.title")) } icon: { Image(systemName: "trophy.fill") }
                        .font(.headline)
                }
                Spacer()
                Toggle(loc.localized("retroAchievements.enable"), isOn: Binding(
                    get: { raService.isEnabled },
                    set: { raService.setEnabled($0) }
                ))
                .toggleStyle(.switch)
            }

            if !raService.isEnabled {
                Text(loc.localized("retroAchievements.enableDescription"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }
        }
        .padding(AppSpacing.xl)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(AppRadius.xl)
    }
    
    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                if isSearching {
                    Text(loc.localized("retroAchievements.account"))
                        .font(.headline)
                } else {
                    Label { Text(loc.localized("retroAchievements.account")) } icon: { Image(systemName: "person.badge.key") }
                        .font(.headline)
                }
                Spacer()
                if raService.isLoggedIn {
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.success(colorScheme)).frame(width: 8, height: 8)
                        Text(loc.localized("retroAchievements.connected"))
                            .font(.caption)
                            .foregroundColor(AppColors.success(colorScheme))
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.textMuted(colorScheme)).frame(width: 8, height: 8)
                        Text(loc.localized("retroAchievements.signInRequired"))
                            .font(.caption)
                            .foregroundColor(AppColors.textMuted(colorScheme))
                    }
                }
            }
            
            if raService.isLoggedIn {
                // Logged in state
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundColor(AppColors.brandAccent)
                        VStack(alignment: .leading) {
                            Text(raService.username ?? loc.localized("retroAchievements.unknown"))
                                .font(.headline)
                            if let userInfo = raService.userInfo {
                                Text(loc.localized("retroAchievements.rankInfo", userInfo.rank, userInfo.totalPoints))
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary(colorScheme))
                            }
                        }
                        Spacer()
                        Button(loc.localized("retroAchievements.logout")) {
                            raService.saveSettings(username: "", webApiKey: "")
                            raService.isLoggedIn = false
                            raService.userInfo = nil
                            username = ""
                            webApiKey = ""
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColors.error(colorScheme))
                    }

                    if let userInfo = raService.userInfo {
                        Divider()
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            HStack {
                                Text(loc.localized("retroAchievements.totalPoints"))
                                Spacer()
                                Text("\(userInfo.totalPoints)")
                                    .fontWeight(.semibold)
                            }
                            HStack {
                                Text(loc.localized("retroAchievements.hardcorePoints"))
                                Spacer()
                                Text("\(userInfo.totalHardcorePoints)")
                                    .fontWeight(.semibold)
                            }
                            HStack {
                                Text(loc.localized("retroAchievements.truePoints"))
                                Spacer()
                                Text("\(userInfo.totalTruePoints)")
                                    .fontWeight(.semibold)
                            }
                            HStack {
                                Text(loc.localized("retroAchievements.memberSince"))
                                Spacer()
                                Text(userInfo.memberSince)
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding(AppSpacing.xl)
                .background(AppColors.cardBackgroundSubtle(colorScheme))
                .cornerRadius(AppRadius.xl)
            } else {
            // Login form
            VStack(spacing: AppSpacing.lg) {
                TextField(loc.localized("retroAchievements.username"), text: $username)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(6)
                    .autocorrectionDisabled()

                SecureField(loc.localized("retroAchievements.password"), text: $password)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(6)

                HStack {
                    if showApiKey {
                        TextField(loc.localized("retroAchievements.webApiKey"), text: $webApiKey)
                            .textFieldStyle(.plain)
                            .padding(6)
                            .background(AppColors.cardBackgroundSubtle(colorScheme))
                            .cornerRadius(6)
                            .autocorrectionDisabled()
                    } else {
                        SecureField(loc.localized("retroAchievements.webApiKey"), text: $webApiKey)
                            .textFieldStyle(.plain)
                            .padding(6)
                            .background(AppColors.cardBackgroundSubtle(colorScheme))
                            .cornerRadius(6)
                    }
                    Button(action: { showApiKey.toggle() }) {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

                    if let error = loginError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(AppColors.error(colorScheme))
                    }

                    Button(action: login) {
                        if isLoggingIn {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(loc.localized("retroAchievements.connect"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoggingIn || username.isEmpty || password.isEmpty || webApiKey.isEmpty)
                }
                .padding(AppSpacing.xl)
                .background(AppColors.cardBackgroundSubtle(colorScheme))
                .cornerRadius(AppRadius.xl)

                Text(loc.localized("retroAchievements.connectDescription"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))

                HStack(spacing: 4) {
                    Text(loc.localized("retroAchievements.findYourKeyAt"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    Link("RetroAchievements Settings", destination: URL(string: "https://retroachievements.org/controlpanel.php")!)
                        .font(.caption)
                }

                HStack(spacing: 4) {
                    Text(loc.localized("retroAchievements.dontHaveAccount"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    Link(loc.localized("retroAchievements.registerHere"), destination: URL(string: "https://retroachievements.org/createaccount.php")!)
                        .font(.caption)
                }
            }
        }
        .padding(AppSpacing.xl)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(AppRadius.xl)
    }
    
    @ViewBuilder
    private var hardcoreModeSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                if isSearching {
                    Text(loc.localized("retroAchievements.hardcoreMode"))
                        .font(.headline)
                } else {
                    Label { Text(loc.localized("retroAchievements.hardcoreMode")) } icon: { Image(systemName: "shield.lefthalf.filled") }
                        .font(.headline)
                }
                Spacer()
                Toggle(loc.localized("retroAchievements.enabled"), isOn: Binding(
                    get: { raService.hardcoreMode },
                    set: { raService.setHardcoreMode($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!raService.isEnabled)
            }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(loc.localized("retroAchievements.hardcoreModeDescription"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))

                VStack(alignment: .leading, spacing: 4) {
                    hardcoreRule(loc.localized("retroAchievements.saveStatesDisabled"))
                    hardcoreRule(loc.localized("retroAchievements.rewindDisabled"))
                    hardcoreRule(loc.localized("retroAchievements.slowMotionDisabled"))
                    hardcoreRule(loc.localized("retroAchievements.cheatCodesDisabled"))
                }

                Text(loc.localized("retroAchievements.softcoreModeWarning"))
                    .font(.caption)
                    .foregroundColor(AppColors.warning(colorScheme))
            }
            .padding(.top, 4)
        }
        .padding(AppSpacing.xl)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(AppRadius.xl)
    }
    
    @ViewBuilder
    private var richPresenceSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                if isSearching {
                    Text(loc.localized("retroAchievements.richPresence"))
                        .font(.headline)
                } else {
                    Label { Text(loc.localized("retroAchievements.richPresence")) } icon: { Image(systemName: "text.bubble.fill") }
                        .font(.headline)
                }
            }

            if let richPresence = raService.richPresence {
                Text(richPresence)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .padding(AppSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(AppRadius.md)
            } else {
                Text(loc.localized("retroAchievements.noGameActive"))
                    .font(.caption)
                    .foregroundColor(AppColors.textMuted(colorScheme))
            }
        }
        .padding(AppSpacing.xl)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(AppRadius.xl)
    }

@ViewBuilder
    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if isSearching {
                    Text(loc.localized("retroAchievements.gameCache"))
                        .font(.headline)
                } else {
                    Label { Text(loc.localized("retroAchievements.gameCache")) } icon: { Image(systemName: "internaldrive") }
                        .font(.headline)
                }
                Spacer()
                if raCacheCoordinator.isActive {
                    ProgressView().controlSize(.small)
                }
            }

            Text(loc.localized("retroAchievements.gameCacheDescription"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))

            HStack(spacing: AppSpacing.xl) {
                Button(action: refreshConsoles) {
                    if isCacheRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label { Text(loc.localized("retroAchievements.refreshSystems")) } icon: { Image(systemName: "arrow.clockwise") }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(raCacheCoordinator.isActive || isCacheRefreshing || !raService.isLoggedIn)

                Button(action: refreshGames) {
                    if isCacheRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label { Text(loc.localized("retroAchievements.refreshGames")) } icon: { Image(systemName: "gamecontroller") }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(raCacheCoordinator.isActive || isCacheRefreshing || !raService.isLoggedIn)

                Button(action: matchAllGames) {
                    if isMatching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label { Text(loc.localized("retroAchievements.matchAllGames")) } icon: { Image(systemName: "trophy") }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(raCacheCoordinator.isActive || isMatching || !raService.isLoggedIn || library.roms.isEmpty)
            }

            if raCacheCoordinator.isActive {
                VStack(alignment: .leading, spacing: 6) {
                    BouncingProgressBar()

                    HStack {
                        Text(raCacheCoordinator.statusLine)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .lineLimit(2)
                        Spacer()
                        if raCacheCoordinator.totalSteps > 0 {
                            Text("\(raCacheCoordinator.currentStep)/\(raCacheCoordinator.totalSteps)")
                                .font(.caption)
                                .foregroundColor(AppColors.textTertiary(colorScheme))
                                .monospacedDigit()
                        }
                    }

                    if raCacheCoordinator.progress > 0 {
                        ProgressView(value: raCacheCoordinator.progress)
                            .progressViewStyle(.linear)
                    }
                }
                .padding(.top, 4)
            }

            if let status = matchingStatus {
                Text(status)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }

            if let error = cacheRefreshError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.error(colorScheme))
            }

            if let lastConsoleDate = AppSettings.get("ra_consoles_cache_date", type: Double.self) {
                let date = Date(timeIntervalSince1970: lastConsoleDate)
                Text(loc.localized("retroAchievements.systemsCached") + " " + date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func refreshConsoles() {
        guard raService.isLoggedIn else {
            cacheRefreshError = loc.localized("retroAchievements.notLoggedIn")
            return
        }
        cacheRefreshError = nil
        isCacheRefreshing = true
        Task {
            do {
                LoggerService.info(category: "RetroAchievements", "[Settings] Refreshing console list...")
                try await raService.fetchAndCacheConsoleList()
                LoggerService.info(category: "RetroAchievements", "[Settings] Console refresh complete.")
            } catch {
                let message = loc.localized("retroAchievements.failedToRefresh", error.localizedDescription)
                LoggerService.error(category: "RetroAchievements", message)
                await MainActor.run {
                    cacheRefreshError = message
                }
            }
            await MainActor.run {
                isCacheRefreshing = false
            }
        }
    }

    private func refreshGames() {
        guard raService.isLoggedIn else {
            cacheRefreshError = loc.localized("retroAchievements.notLoggedIn")
            return
        }
        cacheRefreshError = nil
        isCacheRefreshing = true
        Task {
            do {
                LoggerService.info(category: "RetroAchievements", "[Settings] Refreshing all game lists (this may take a while)...")
                try await raService.fetchAndCacheAllGames()
                LoggerService.info(category: "RetroAchievements", "[Settings] Game list refresh complete.")
            } catch {
                let message = loc.localized("retroAchievements.failedToRefresh", error.localizedDescription)
                LoggerService.error(category: "RetroAchievements", message)
                await MainActor.run {
                    cacheRefreshError = message
                }
            }
            await MainActor.run {
                isCacheRefreshing = false
            }
        }
    }

    private func matchAllGames() {
        guard raService.isLoggedIn else {
            matchingStatus = loc.localized("retroAchievements.notLoggedIn")
            return
        }
        matchingStatus = nil
        isMatching = true
        Task {
            let (matched, total) = await raService.matchAllCachedGames(roms: library.roms)
            await MainActor.run {
                isMatching = false
                matchingStatus = loc.localized("retroAchievements.matchedOfTotal", matched, total)
            }
        }
    }
    
    @ViewBuilder
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSearching {
                Text(loc.localized("retroAchievements.about"))
                    .font(.headline)
            } else {
                Label { Text(loc.localized("retroAchievements.about")) } icon: { Image(systemName: "info.circle") }
                    .font(.headline)
            }
            
	Text(loc.localized("retroAchievements.aboutDescription"))
			.font(.caption)
			.foregroundColor(AppColors.textSecondary(colorScheme))
            
            Link(loc.localized("retroAchievements.visitWebsite"), destination: URL(string: "https://retroachievements.org")!)
		.font(.caption)
		}
		.padding(AppSpacing.xl)
		.background(AppColors.cardBackgroundSubtle(colorScheme))
		.cornerRadius(AppRadius.xl)
	}
    
	private func hardcoreRule(_ text: String) -> some View {
		HStack(spacing: AppSpacing.md) {
			Image(systemName: "xmark.circle.fill")
				.foregroundColor(AppColors.error(colorScheme).opacity(0.7))
				.font(.caption)
			Text(text)
				.font(.caption)
				.foregroundColor(AppColors.textSecondary(colorScheme))
        }
    }
    
    private func login() {
        isLoggingIn = true
        loginError = nil

        Task {
            do {
                try await raService.loginWithWebApiKey(username: username, webApiKey: webApiKey, password: password)
                await MainActor.run {
                    isLoggingIn = false
                    password = ""
                    webApiKey = ""
                }
            } catch {
                await MainActor.run {
                    isLoggingIn = false
                    loginError = error.localizedDescription
                }
            }
        }
    }
}
