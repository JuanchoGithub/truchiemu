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
        if SettingsSearchRuntime.pageMatches(.retroAchievements, query: searchText) { return true }
        return SettingsIndex.matches(haystack: text, query: searchText)
    }
    
    private func highlightText(_ text: String) -> String {
        return text
    }
    
    var body: some View {
        Form {
            // Enable
            if !isSearching || matchesSearch("RetroAchievements enable disable") {
                Section {
                    Toggle(loc.localized("retroAchievements.enable"), isOn: Binding(
                        get: { raService.isEnabled },
                        set: { raService.setEnabled($0) }
                    ))
                    if !raService.isEnabled {
                        Text(loc.localized("retroAchievements.enableDescription"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                } header: {
                    Label(loc.localized("retroAchievements.title"), systemImage: "trophy.fill")
                }
            }

            // Account
            if !isSearching || matchesSearch("account username login logout connect api key") {
                Section {
                    if raService.isLoggedIn {
                        LoggedInAccountContent()
                    } else {
                        LoginFormContent(
                            username: $username,
                            password: $password,
                            webApiKey: $webApiKey,
                            showApiKey: $showApiKey,
                            loginError: loginError,
                            isLoggingIn: isLoggingIn,
                            onLogin: login
                        )
                    }
                } header: {
                    Label(loc.localized("retroAchievements.account"), systemImage: "person.badge.key")
                }
            }

            // Hardcore Mode
            if !isSearching || matchesSearch("hardcore mode") {
                Section {
                    Toggle(loc.localized("retroAchievements.enabled"), isOn: Binding(
                        get: { raService.hardcoreMode },
                        set: { newValue in
                            if newValue {
                                raService.setHardcoreMode(true)
                                HardcoreModeManager.shared.activateHardcore()
                            } else {
                                HardcoreModeManager.shared.deactivateHardcore()
                                raService.setHardcoreMode(false)
                            }
                        }
                    ))
                    .disabled(!raService.isEnabled)

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
                } header: {
                    Label(loc.localized("retroAchievements.hardcoreMode"), systemImage: "shield.lefthalf.filled")
                }
            }

            // Display
            if !isSearching || matchesSearch("display view grid list achievements") {
                Section {
                    Picker(loc.localized("achievement.defaultViewMode"), selection: Binding<AchievementViewMode>(
                        get: {
                            if let raw = AppSettings.getString("achievementViewMode") {
                                AchievementViewMode(rawValue: raw) ?? .grid
                            } else { .grid }
                        },
                        set: { newMode in
                            AppSettings.setString("achievementViewMode", value: newMode.rawValue)
                        }
                    )) {
                        ForEach(AchievementViewMode.allCases, id: \.self) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(loc.localized("achievement.defaultViewModeDescription"))
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                } header: {
                    Label(loc.localized("achievement.display"), systemImage: "eye")
                }
            }

            // Rich Presence
            if !isSearching || matchesSearch("rich presence game active") {
                Section {
                    if let richPresence = raService.richPresence {
                        Text(richPresence)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    } else {
                        Text(loc.localized("retroAchievements.noGameActive"))
                            .font(.caption)
                            .foregroundColor(AppColors.textMuted(colorScheme))
                    }
                } header: {
                    Label(loc.localized("retroAchievements.richPresence"), systemImage: "text.bubble.fill")
                }
            }

            // Game Cache
            if !isSearching || matchesSearch("refresh cache systems games data") {
                Section {
                    CacheSectionContent(
                        isCacheRefreshing: $isCacheRefreshing,
                        isMatching: $isMatching,
                        cacheRefreshError: cacheRefreshError,
                        matchingStatus: matchingStatus,
                        onRefreshConsoles: refreshConsoles,
                        onRefreshGames: refreshGames,
                        onMatchAllGames: matchAllGames
                    )
                } header: {
                    Label(loc.localized("retroAchievements.gameCache"), systemImage: "internaldrive")
                }
            }

            // About
            if !isSearching || matchesSearch("about info") {
                Section {
                    Text(loc.localized("retroAchievements.aboutDescription"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    Link(loc.localized("retroAchievements.visitWebsite"), destination: URL(string: "https://retroachievements.org")!)
                        .font(.caption)
                } header: {
                    Label(loc.localized("retroAchievements.about"), systemImage: "info.circle")
                }
            }

            if isSearching && !hasAnyResults {
                Section {
                    ContentUnavailableView(
                        loc.localized("retroAchievements.noResults"),
                        systemImage: "magnifyingglass",
                        description: Text(loc.localized("retroAchievements.tryAdjustingSearch"))
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .navigationTitle(loc.localized("retroAchievements.title"))
    }

    @ViewBuilder
    private func LoggedInAccountContent() -> some View {
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
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    LabeledContent(loc.localized("retroAchievements.totalPoints"), value: "\(userInfo.totalPoints)")
                    LabeledContent(loc.localized("retroAchievements.hardcorePoints"), value: "\(userInfo.totalHardcorePoints)")
                    LabeledContent(loc.localized("retroAchievements.truePoints"), value: "\(userInfo.totalTruePoints)")
                    LabeledContent(loc.localized("retroAchievements.memberSince"), value: userInfo.memberSince)
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func LoginFormContent(
        username: Binding<String>,
        password: Binding<String>,
        webApiKey: Binding<String>,
        showApiKey: Binding<Bool>,
        loginError: String?,
        isLoggingIn: Bool,
        onLogin: @escaping () -> Void
    ) -> some View {
        VStack(spacing: AppSpacing.lg) {
            TextField(loc.localized("retroAchievements.username"), text: username)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()

            SecureField(loc.localized("retroAchievements.password"), text: password)
                .textFieldStyle(.plain)

            HStack {
                if showApiKey.wrappedValue {
                    TextField(loc.localized("retroAchievements.webApiKey"), text: webApiKey)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                } else {
                    SecureField(loc.localized("retroAchievements.webApiKey"), text: webApiKey)
                        .textFieldStyle(.plain)
                }
                Button(action: { showApiKey.wrappedValue.toggle() }) {
                    Image(systemName: showApiKey.wrappedValue ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
            }

            if let error = loginError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.error(colorScheme))
            }

            Button(action: onLogin) {
                if isLoggingIn {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(loc.localized("retroAchievements.connect"))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoggingIn || username.wrappedValue.isEmpty || password.wrappedValue.isEmpty || webApiKey.wrappedValue.isEmpty)
        }

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

    @ViewBuilder
    private func CacheSectionContent(
        isCacheRefreshing: Binding<Bool>,
        isMatching: Binding<Bool>,
        cacheRefreshError: String?,
        matchingStatus: String?,
        onRefreshConsoles: @escaping () -> Void,
        onRefreshGames: @escaping () -> Void,
        onMatchAllGames: @escaping () -> Void
    ) -> some View {
        Text(loc.localized("retroAchievements.gameCacheDescription"))
            .font(.caption)
            .foregroundColor(AppColors.textSecondary(colorScheme))

        HStack(spacing: AppSpacing.xl) {
            Button(action: onRefreshConsoles) {
                if isCacheRefreshing.wrappedValue {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(loc.localized("retroAchievements.refreshSystems"), systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(raCacheCoordinator.isActive || isCacheRefreshing.wrappedValue || !raService.isLoggedIn)

            Button(action: onRefreshGames) {
                if isCacheRefreshing.wrappedValue {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(loc.localized("retroAchievements.refreshGames"), systemImage: "gamecontroller")
                }
            }
            .buttonStyle(.bordered)
            .disabled(raCacheCoordinator.isActive || isCacheRefreshing.wrappedValue || !raService.isLoggedIn)

            Button(action: onMatchAllGames) {
                if isMatching.wrappedValue {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(loc.localized("retroAchievements.matchAllGames"), systemImage: "trophy")
                }
            }
            .buttonStyle(.bordered)
            .disabled(raCacheCoordinator.isActive || isMatching.wrappedValue || !raService.isLoggedIn || library.roms.isEmpty)
        }

        if raCacheCoordinator.isActive {
            VStack(alignment: .leading, spacing: 6) {
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
    
    private var hasAnyResults: Bool {
        matchesSearch("RetroAchievements enable disable") ||
        matchesSearch("account username login logout connect api key") ||
        matchesSearch("refresh cache systems games data") ||
        matchesSearch("hardcore mode") ||
        matchesSearch("display view grid list achievements") ||
        matchesSearch("rich presence game active") ||
        matchesSearch("about info")
    }
    
    // MARK: - Section Views

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
