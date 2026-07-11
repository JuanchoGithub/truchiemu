import SwiftUI

struct MoveListOverlay: View {
    @ObservedObject var viewModel: MoveListOverlayViewModel
    @ObservedObject var windowController: StandaloneGameWindowController
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var panelOffset = CGSize(
        width: AppSettings.getDouble("moveListPanelOffsetX"),
        height: AppSettings.getDouble("moveListPanelOffsetY")
    )
    @State private var panelBaseOffset = CGSize(
        width: AppSettings.getDouble("moveListPanelOffsetX"),
        height: AppSettings.getDouble("moveListPanelOffsetY")
    )

    var body: some View {
        Group {
            if viewModel.needsCharacterSelection {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            viewModel.showCharacterSelection()
                        }
                    characterSelectionPanel
                }
            } else if viewModel.isOverlayVisible {
                moveListPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var characterSelectionPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text(loc.localized("movelist.selectCharacter"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    Divider()

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(viewModel.characters) { character in
                                characterRow(character)
                            }
                        }
                    }
                }
                .frame(width: 280)

                Divider()

                if viewModel.enabledCharacterName != nil {
                    rightMovePanel
                } else {
                    notationLegendSidebar
                }
            }

            Divider()

            inputSequenceSection
                .padding(.horizontal, 8)
                .padding(.vertical, 2)

            HStack(spacing: 12) {
                Button(action: {
                    windowController.toggleMoveListOverlay()
                }) {
                    Text(loc.localized("movelist.cancel"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 580, height: min(CGFloat(viewModel.characters.count) * 36 + 160, 380))
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 10)
        .padding(.bottom, windowController.toolbarBottomInset)
    }

    private var rightMovePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            inlineHeaderSection

            ScrollView {
                moveListSection
            }
        }
    }

    private var inlineHeaderSection: some View {
        HStack(spacing: 6) {
            if let charName = viewModel.selectedCharacterName {
                Text(charName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.brandAccent)
                    .lineLimit(1)
            }

            Spacer()

            Picker("", selection: Binding(
                get: { viewModel.buttonDisplayMode },
                set: { newValue in
                    AppSettings.set(ButtonDisplayMode.settingsKey, value: newValue.rawValue)
                    viewModel.refreshButtonKeyLabels()
                }
            )) {
                Text(loc.localized("settings.moveList.buttonDisplay.symbol"))
                    .tag(ButtonDisplayMode.symbol)
                Text(loc.localized("settings.moveList.buttonDisplay.consoleButton"))
                    .tag(ButtonDisplayMode.consoleButton)
                Text(loc.localized("settings.moveList.buttonDisplay.inputKey"))
                    .tag(ButtonDisplayMode.inputKey)
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .tint(AppColors.brandAccent)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func characterRow(_ character: FightDataCharacter) -> some View {
        let isExpanded = viewModel.expandedCharacterId == character.id
        let isEnabled = viewModel.enabledCharacterName == character.name

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(character.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isEnabled ? AppColors.brandAccent : .white)

                Spacer()

                if isEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.brandAccent)
                }

                let sections = viewModel.sectionsForCharacter(character)
                let enabledCount = sections.filter { viewModel.isSectionEnabled(characterName: character.name, section: $0) }.count
                if enabledCount < sections.count {
                    Text(verbatim: "\(enabledCount)/\(sections.count)")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.toggleExpandCharacter(character)
                    }
                }) {
                    Text(loc.localized("movelist.set"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AppColors.brandAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppColors.brandAccent.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? AppColors.brandAccent.opacity(0.12) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.toggleCharacter(character)
            }

            if isExpanded {
                characterSectionsView(character)
            }

            Divider().opacity(0.3)
        }
    }

    @ViewBuilder
    private func characterSectionsView(_ character: FightDataCharacter) -> some View {
        let sections = viewModel.sectionsForCharacter(character)

        VStack(spacing: 0) {
            ForEach(sections, id: \.self) { section in
                let isEnabled = viewModel.isSectionEnabled(characterName: character.name, section: section)

                HStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { isEnabled },
                        set: { _ in
                            viewModel.toggleSection(characterName: character.name, section: section)
                        }
                    )) {
                        Text(viewModel.sectionLabel(section))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isEnabled ? .white : .white.opacity(0.4))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(AppColors.brandAccent)

                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                Button(action: {
                    viewModel.enableAllSections(characterName: character.name, sections: sections)
                }) {
                    Text(loc.localized("movelist.enableAll"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AppColors.brandAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppColors.brandAccent.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.disableAllSections(characterName: character.name, sections: sections)
                }) {
                    Text(loc.localized("movelist.disableAll"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    windowController.confirmAndShowOverlay(character: character)
                }) {
Text(loc.localized("movelist.saveAndSelect"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppColors.textOnAccent(colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.brandAccent)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 4)
        }
        .padding(.bottom, 4)
    }

    private var notationLegendSidebar: some View {
        let abbr = viewModel.moveListService.controlAbbreviations
        let labels = viewModel.moveListService.controlLabels
        let cats = viewModel.moveListService.categoryLabels
        let buttonEntries = abbr.sorted(by: { $0.key > $1.key }).filter { key, _ in
            key != "_S" && key != "^S" && labels[key] != nil
        }
        let catEntries = cats.sorted(by: { $0.key < $1.key })

        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.localized("movelist.notationLegend"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 13)

                if !buttonEntries.isEmpty {
                    Text(loc.localized("movelist.buttons"))
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))

                    ForEach(buttonEntries, id: \.key) { key, a in
                        HStack(spacing: 3) {
                MoveNotationTokenView(
                    token: {
                        let btnType = MoveNotationRenderer.resolveButtonType(key, gameData: viewModel.moveListService.currentGameData)
                        if let kl = viewModel.buttonKeyLabels[key] {
                            return .buttonKeyLabel(btnType, keyLabel: kl)
                        }
                        return .button(btnType)
                    }(),
                    isHighlighted: true,
                    compact: true
                )
                            Text(labels[key] ?? "")
                                .font(.system(size: 7))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                }

                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(loc.localized("movelist.symbols"))
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))

                    HStack(spacing: 3) {
                        MoveNotationTokenView(token: .air, isHighlighted: true, compact: true)
                        Text(verbatim: "= Air").font(.system(size: 7)).foregroundColor(.white.opacity(0.4))
                    }
                    HStack(spacing: 3) {
                        MoveNotationTokenView(token: .charge(.down), isHighlighted: true, compact: true)
                        Text(verbatim: "= Hold/Charge").font(.system(size: 7)).foregroundColor(.white.opacity(0.4))
                    }
                    HStack(spacing: 3) {
                        MoveNotationTokenView(token: .wait, isHighlighted: true, compact: true)
                        Text(verbatim: "= Wait/Neutral").font(.system(size: 7)).foregroundColor(.white.opacity(0.4))
                    }
                    HStack(spacing: 3) {
                        MoveNotationTokenView(token: .rapidPress, isHighlighted: true, compact: true)
                        Text(verbatim: "= Rapid press").font(.system(size: 7)).foregroundColor(.white.opacity(0.4))
                    }
                    HStack(spacing: 3) {
                        MoveNotationTokenView(token: .motion(.quarterCircle(from: .down)), isHighlighted: true, compact: true)
                        Text(verbatim: "= Quarter circle").font(.system(size: 7)).foregroundColor(.white.opacity(0.4))
                    }
                HStack(spacing: 3) {
                    MoveNotationTokenView(token: .motion(.halfCircle(from: .left)), isHighlighted: true, compact: true)
                    Text(verbatim: "= Half circle").font(.system(size: 7)).foregroundColor(.white.opacity(0.4))
                }
                HStack(spacing: 3) {
                    MoveNotationTokenView(token: .motion360, isHighlighted: true, compact: true)
                    Text(verbatim: "= 360 rotation").font(.system(size: 7)).foregroundColor(.white.opacity(0.4))
                }
                HStack(spacing: 3) {
                    MoveNotationTokenView(token: .standClose, isHighlighted: true, compact: true)
                    Text(verbatim: "= Close range").font(.system(size: 7)).foregroundColor(.white.opacity(0.4))
                }
                }

                if !catEntries.isEmpty {
                    Divider().opacity(0.3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("movelist.categories"))
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))

                        ForEach(catEntries, id: \.key) { key, label in
                            HStack {
                                Text(key.replacingOccurrences(of: "_", with: ""))
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.3))
                                    .frame(width: 14, alignment: .leading)
                                Text(label)
                                    .font(.system(size: 7))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 11)
        }
    }

    private var moveListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            ScrollView {
                moveListSection
            }

            inputSequenceSection
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
        .frame(maxHeight: 320)
        .background(.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .offset(panelOffset)
        .onReceive(NotificationCenter.default.publisher(for: .resetMoveListOverlayPosition)) { _ in
            let zero = CGSize.zero
            panelOffset = zero
            panelBaseOffset = zero
            AppSettings.setDouble("moveListPanelOffsetX", value: 0)
            AppSettings.setDouble("moveListPanelOffsetY", value: 0)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    panelOffset = CGSize(
                        width: panelBaseOffset.width + value.translation.width,
                        height: panelBaseOffset.height + value.translation.height
                    )
                }
                .onEnded { value in
                    let newOffset = CGSize(
                        width: panelBaseOffset.width + value.translation.width,
                        height: panelBaseOffset.height + value.translation.height
                    )
                    panelOffset = newOffset
                    panelBaseOffset = newOffset
                    AppSettings.setDouble("moveListPanelOffsetX", value: Double(newOffset.width))
                    AppSettings.setDouble("moveListPanelOffsetY", value: Double(newOffset.height))
                }
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.isOverlayVisible)
    }

    private var headerSection: some View {
        HStack(spacing: 6) {
            Button(action: {
                viewModel.showCharacterSelection()
            }) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.brandAccent)
            }
            .buttonStyle(.plain)
            .help(loc.localized("movelist.backToCharacters"))

            Button(action: {
                windowController.toggleMoveListOverlay()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            if let charName = viewModel.selectedCharacterName, viewModel.characters.first(where: { $0.name == charName }) != nil {
                Text(charName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.brandAccent)
                    .lineLimit(1)
                    .onTapGesture {
                        windowController.deselectCurrentCharacter()
                    }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var moveListSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(viewModel.filteredMoves.enumerated()), id: \.offset) { _, move in
                MoveEntryRow(
                    move: move,
                    isMatched: viewModel.matchedMoveName == move.name,
                    showMoveNames: viewModel.showMoveNames
                )
            }

            if viewModel.filteredMoves.isEmpty {
                Spacer()
            }
        }
        .padding(.vertical, 3)
    }

private var inputSequenceSection: some View {
        let hasContent = viewModel.hasActiveInput
        return HStack(spacing: NotationMetrics.tokenSpacing) {
            if hasContent {
                ForEach(Array(viewModel.inputSteps.enumerated()), id: \.offset) { _, step in
                    switch step {
                    case .direction(let dir, let isCharge):
                        if isCharge {
                            MoveNotationTokenView(token: .charge(dir), isHighlighted: true, compact: true)
                        } else {
                            MoveNotationTokenView(token: .direction(dir), isHighlighted: true, compact: true)
                        }
                    case .motion(let motionType):
                        MoveNotationTokenView(token: .motion(motionType), isHighlighted: true, compact: true)
                    case .buttons(let btns):
                        let btnTokens = buildInputButtonTokens(btns)
                        ForEach(Array(btnTokens.enumerated()), id: \.offset) { _, token in
                            MoveNotationTokenView(token: token, isHighlighted: true, compact: true)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hasContent ? Color.black.opacity(0.6) : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hasContent ? AppColors.brandAccent.opacity(0.4) : .clear, lineWidth: 1)
            )
        )
    }

    private var notesSection: some View {
        Group {
            if viewModel.inputSteps.isEmpty {
                if !viewModel.commonNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.commonNotes, id: \.self) { note in
                            Text(note)
                                .font(.system(size: 7))
                                .foregroundColor(.white.opacity(0.35))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 3)
                }
                if !viewModel.cheatNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("movelist.cheatNotes"))
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                        ForEach(viewModel.cheatNotes, id: \.self) { note in
                            Text(note)
                                .font(.system(size: 7))
                                .foregroundColor(.white.opacity(0.3))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 3)
                }
            }
        }
    }

    private func buildInputButtonTokens(_ buttons: Set<String>) -> [NotationToken] {
        var tokens: [NotationToken] = []
        let sorted = buttons.sorted()
        let keyLabels = viewModel.buttonKeyLabels
        for (i, key) in sorted.enumerated() {
            if i > 0 { tokens.append(.separator) }
            let btnType = MoveNotationRenderer.resolveButtonType(key, gameData: viewModel.moveListService.currentGameData)
            if let kl = keyLabels[key] {
                tokens.append(.buttonKeyLabel(btnType, keyLabel: kl))
            } else {
                tokens.append(.button(btnType))
            }
        }
        return tokens
    }
}

struct MoveEntryRow: View {
    let move: ResolvedMove
    let isMatched: Bool
    let showMoveNames: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            MoveNotationTokenRow(
                tokens: move.tokens,
                matchedStepCount: move.matchedStepCount,
                compact: false
            )

        VStack(alignment: .leading, spacing: 1) {
            if showMoveNames {
                if !move.name.isEmpty {
                    Text(move.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isMatched ? AppColors.brandAccent : .white)
                }
                HStack(spacing: 2) {
                    if move.isAir {
                        Text(verbatim: "AIR")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    }
                    if move.isCharge {
                        Text(verbatim: "CHARGE")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.yellow.opacity(0.6))
                    }
                    if let cond = move.condition {
                        Text(cond)
                            .font(.system(size: 6))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    Text(move.categoryLabel)
                        .font(.system(size: 6))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            }
            .padding(.leading, 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isMatched ? AppColors.brandAccent.opacity(0.6) : .clear,
                            lineWidth: 1
                        )
                )
        )
        .overlay(alignment: .leading) {
            if isMatched {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.brandAccent)
                    .frame(width: 3, height: 16)
                    .offset(x: -1)
            }
        }
    }
}
