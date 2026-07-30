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
    @State private var showEnablePrompt = false
    @State private var enableHardcore = false
    
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?
    let system: SystemInfo?

    init(searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil), system: SystemInfo? = nil) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
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

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                // Enable
                if (!isSearching || matchesSearch("RetroAchievements enable disable")) && sectionVisible("section-enable") {
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
                    .id("section-enable")
                }

                // Account
                if (!isSearching || matchesSearch("account username login logout connect api key")) && sectionVisible("section-account") {
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
                    .id("section-account")
                }

                // Hardcore Mode
                if (!isSearching || matchesSearch("hardcore mode")) && sectionVisible("section-hardcore") {
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
                            hardcoreRule(loc.localized("retroAchievements.fastForwardDisabled"))
                            hardcoreRule(loc.localized("retroAchievements.cheatCodesDisabled"))
                        }

                        Text(loc.localized("retroAchievements.softcoreModeWarning"))
                            .font(.caption)
                            .foregroundColor(AppColors.warning(colorScheme))
                    } header: {
                        Label(loc.localized("retroAchievements.hardcoreMode"), systemImage: "shield.lefthalf.filled")
                    }
                    .id("section-hardcore")
                }

                // Display
                if (!isSearching || matchesSearch("display view grid list achievements")) && sectionVisible("section-display") {
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
                    .id("section-display")
                }

                // Rich Presence
                if (!isSearching || matchesSearch("rich presence game active")) && sectionVisible("section-richPresence") {
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
                    .id("section-richPresence")
                }

                // Game Cache
                if (!isSearching || matchesSearch("refresh cache systems games data")) && sectionVisible("section-refresh") {
                    Section {
                        CacheSectionContent(
                            isCacheRefreshing: $isCacheRefreshing,
                            cacheRefreshError: cacheRefreshError,
                            matchingStatus: matchingStatus,
                            onRefreshConsoles: refreshConsoles,
                            onRefreshGames: refreshGames,
                            onMatchAllGames: matchAllGames
                        )
                    } header: {
                        Label(loc.localized("retroAchievements.gameCache"), systemImage: "internaldrive")
                    }
                    .id("section-refresh")
                }

                // About
                if (!isSearching || matchesSearch("about info")) && sectionVisible("section-about") {
                    Section {
                        Text(loc.localized("retroAchievements.aboutDescription"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Link(loc.localized("retroAchievements.visitWebsite"), destination: URL(string: "https://retroachievements.org")!)
                            .font(.caption)
                    } header: {
                        Label(loc.localized("retroAchievements.about"), systemImage: "info.circle")
                    }
                    .id("section-about")
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
            .onChange(of: focusedSectionID) { _, newID in
                guard let id = newID else { return }
                withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
            }
            .onChange(of: scopedSectionID) { _, newScope in
                guard let id = newScope else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
                }
            }
            .sheet(isPresented: $showEnablePrompt) {
                EnableRetroAchievementsPromptView(enableHardcore: $enableHardcore) {
                    raService.setEnabled(true)
                    if enableHardcore {
                        raService.setHardcoreMode(true)
                        HardcoreModeManager.shared.activateHardcore()
                    }
                }
            }
        }
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
                Button {
                    Task { await raService.refreshUserSummary() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help(loc.localized("retroAchievements.refreshStats"))
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
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            SecureField(loc.localized("retroAchievements.password"), text: password)
                .textFieldStyle(.roundedBorder)

            HStack {
                if showApiKey.wrappedValue {
                    TextField(loc.localized("retroAchievements.webApiKey"), text: webApiKey)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                } else {
                    SecureField(loc.localized("retroAchievements.webApiKey"), text: webApiKey)
                        .textFieldStyle(.roundedBorder)
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
                Label(loc.localized("retroAchievements.matchAllGames"), systemImage: "trophy")
            }
            .buttonStyle(.bordered)
            .disabled(raCacheCoordinator.isActive || raService.isMatchingAll || !raService.isLoggedIn)
        }

        if raService.isMatchingAll {
            VStack(alignment: .leading, spacing: 6) {
                BouncingProgressBar()
                if raService.isImportingRACache {
                    // Cache-import phase: show files-progress instead of the
                    // matched counter (which is still 0 of N during import).
                    let format = loc.localized("retroAchievements.importingCacheProgress")
                    Text(format
                        .replacingOccurrences(of: "{0}", with: "\(raService.importRACacheStep)")
                        .replacingOccurrences(of: "{1}", with: "\(raService.importRACacheTotal)"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                } else {
                    let format = loc.localized("retroAchievements.matchedOfTotal")
                    Text(format
                        .replacingOccurrences(of: "{0}", with: "\(raService.matchedAllCount)")
                        .replacingOccurrences(of: "{1}", with: "\(raService.matchedAllTotal)"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
            }
        }

        if raCacheCoordinator.isActive && !raService.isMatchingAll {
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
        Task {
            let (matched, total) = await raService.matchAllCachedGames(roms: library.roms)
            await MainActor.run {
                raService.isMatchingAll = false
                let format = loc.localized("retroAchievements.matchedOfTotal")
                matchingStatus = format
                    .replacingOccurrences(of: "{0}", with: "\(matched)")
                    .replacingOccurrences(of: "{1}", with: "\(total)")
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
                    if !raService.isEnabled {
                        enableHardcore = false
                        showEnablePrompt = true
                    }
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

// MARK: - Enable Prompt Sheet

private struct EnableRetroAchievementsPromptView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Binding var enableHardcore: Bool
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(loc.localized("retroAchievements.enableAfterLoginTitle"))
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                Text(loc.localized("retroAchievements.enableAfterLoginMessage"))
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Toggle(loc.localized("retroAchievements.enableAfterLoginHardcore"), isOn: $enableHardcore)
                    .tint(AppColors.brandAccent)
                Text(loc.localized("retroAchievements.enableAfterLoginHardcoreDescription"))
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: AppSpacing.md) {
                Spacer()
                Button(loc.localized("general.cancel"), role: .cancel) {
                    dismiss()
                }
                Button(loc.localized("retroAchievements.enable")) {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.brandAccent)
            }
        }
        .padding(AppSpacing.xl2)
        .frame(width: 380)
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
    }
}
