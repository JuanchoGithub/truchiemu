import SwiftUI

struct TrainingModeOverlay: View {
    @ObservedObject var viewModel: TrainingModeOverlayViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.closeOverlay()
                }

            VStack(spacing: 0) {
                headerBar
                if viewModel.isP2Joining {
                    p2JoinStatusBar
                }
                tabContent
            }
            .frame(maxWidth: 480, maxHeight: 520)
            .background(AppColors.cardBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 10)
            .padding(.bottom, viewModel.toolbarBottomMargin)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(viewModel.isMenuVisible)
    }

    private var headerBar: some View {
        VStack(spacing: 0) {
        HStack(spacing: 8) {
            Text(loc.localized("toolbar.fightTraining"))
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            if viewModel.isTrainingEnabled {
                Button {
                    viewModel.triggerP2Join()
                } label: {
                    if viewModel.isP2Joining {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(loc.localized("training.p2Join.joining"))
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.5))
                        .cornerRadius(6)
                        .foregroundColor(.white.opacity(0.7))
                    } else {
                        Label(loc.localized("training.p2Join"), systemImage: "person.2.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
.background(AppColors.brandAccent.opacity(0.8))
                        .cornerRadius(6)
                        .foregroundColor(AppColors.textOnAccent(colorScheme))
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isP2Joining)
            }

            Button {
                    viewModel.toggleTraining()
                } label: {
                    Text(viewModel.isTrainingEnabled ? loc.localized("training.disable") : loc.localized("training.enable"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
.background(viewModel.isTrainingEnabled ? Color.red.opacity(0.8) : AppColors.brandAccent.opacity(0.8))
                    .cornerRadius(6)
                    .foregroundColor(viewModel.isTrainingEnabled ? .white : AppColors.textOnAccent(colorScheme))
                }
                .buttonStyle(.plain)

            Button {
                viewModel.closeOverlay()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColors.toolbarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))

            Divider()

            tabPicker

            Divider()
        }
    }

    private var p2JoinStatusBar: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
            if let statusText = viewModel.p2JoinStatusText {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.brandAccent)
            } else {
                Text(loc.localized("training.p2Join.joining"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.brandAccent)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(AppColors.brandAccent.opacity(0.08))
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(TrainingModeOverlayViewModel.TrainingTab.allCases, id: \.rawValue) { tab in
                Button {
                    viewModel.selectedTab = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tabIcon(tab))
                            .font(.system(size: 12))
                        Text(tabLabel(tab))
                            .font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(viewModel.selectedTab == tab ? AppColors.brandAccent.opacity(0.15) : Color.clear)
                    .foregroundColor(viewModel.selectedTab == tab ? AppColors.brandAccent : AppColors.textSecondaryNeutral(colorScheme))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }

    private var tabContent: some View {
        ScrollView {
            switch viewModel.selectedTab {
            case .dummy: TrainingDummyTab(viewModel: viewModel)
            case .sequence: TrainingSequenceTab(viewModel: viewModel)
            case .recording: TrainingRecordingTab(viewModel: viewModel)
            case .settings: TrainingSettingsTab(viewModel: viewModel)
            case .display: TrainingDisplayTab(viewModel: viewModel)
            case .moves: TrainingMovesTab(viewModel: viewModel)
            }
        }
        .padding(16)
    }

    private func tabIcon(_ tab: TrainingModeOverlayViewModel.TrainingTab) -> String {
        switch tab {
        case .dummy: return "figure.stand"
        case .sequence: return "list.number"
        case .recording: return "record.circle"
        case .settings: return "gearshape"
        case .display: return "tv"
        case .moves: return "list.bullet.rectangle"
        }
    }

    private func tabLabel(_ tab: TrainingModeOverlayViewModel.TrainingTab) -> String {
        switch tab {
        case .dummy: return loc.localized("training.tab.dummy")
        case .sequence: return loc.localized("training.tab.sequence")
        case .recording: return loc.localized("training.tab.recording")
        case .settings: return loc.localized("training.tab.settings")
        case .display: return loc.localized("training.tab.display")
        case .moves: return loc.localized("training.tab.moves")
        }
    }
}

struct TrainingDummyTab: View {
    @ObservedObject var viewModel: TrainingModeOverlayViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingReversalPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlModeSection
            stanceSection
            guardSection
            if let blockLabel = viewModel.blockButtonLabel {
                blockButtonInfoSection(blockLabel)
            }
            if viewModel.isGenesisSystem {
                genesisThreeButtonSection
            }
            facingSection
            wakeUpTechSection
            reversalActionSection
        }
    }

    private var controlModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.controlMode"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.controlMode) {
                ForEach(TrainingControlMode.allCases, id: \.self) { mode in
                    Text(controlModeLabel(mode)).tag(mode)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.isTrainingEnabled)
        }
    }

    private var stanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.stance"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.stance) {
                ForEach(TrainingStance.allCases, id: \.self) { s in
                    Text(stanceLabel(s)).tag(s)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.isTrainingEnabled)
        }
    }

    private var guardSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.guard"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.guardMode) {
                ForEach(TrainingGuard.allCases, id: \.self) { g in
                    Text(guardLabel(g)).tag(g)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.isTrainingEnabled)
        }
    }

    private func blockButtonInfoSection(_ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 11))
                .foregroundColor(AppColors.brandAccent)
            Text(loc.localized("training.guard.blockButton"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.brandAccent)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(AppColors.brandAccent.opacity(0.06))
        .cornerRadius(6)
    }

    private var facingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.facing"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.p2FacesRight) {
                Text(loc.localized("training.facing.left")).tag(false)
                Text(loc.localized("training.facing.right")).tag(true)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.isTrainingEnabled)
        }
    }

    private var genesisThreeButtonSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.genesis.controller"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.genesisThreeButtonMode) {
                Text(loc.localized("training.genesis.6button")).tag(false)
                Text(loc.localized("training.genesis.3button")).tag(true)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.isTrainingEnabled)
        }
    }

    private var wakeUpTechSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.wakeUpTech"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.wakeUpTech) {
                ForEach(TrainingWakeUpTech.allCases, id: \.self) { tech in
                    Text(wakeUpTechLabel(tech)).tag(tech)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.isTrainingEnabled)
        }
    }

    private var reversalActionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.reversalAction"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            if viewModel.reversalMoveId != nil {
                HStack {
                    Text(viewModel.reversalMoveName ?? loc.localized("training.reversalAction.selected"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.brandAccent)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        showingReversalPicker = true
                    } label: {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.clearReversalMove()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(AppColors.cardBackground(colorScheme).opacity(0.5))
                .cornerRadius(6)
            } else {
                Button {
                    showingReversalPicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                            .foregroundColor(AppColors.brandAccent)
                        Text(loc.localized("training.reversalAction.selectMove"))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.availableMovesForReversal.isEmpty)
            }
        }
        .sheet(isPresented: $showingReversalPicker) {
            ReversalMovePickerSheet(viewModel: viewModel)
                .gamepadDismissable { showingReversalPicker = false }
        }
    }

    private func controlModeLabel(_ mode: TrainingControlMode) -> String {
        switch mode {
        case .standby: return loc.localized("training.control.standby")
        case .human: return loc.localized("training.control.human")
        case .stanceGuard: return loc.localized("training.control.stanceGuard")
        case .fmdSequence: return loc.localized("training.control.fmdSequence")
        }
    }

    private func stanceLabel(_ stance: TrainingStance) -> String {
        switch stance {
        case .stand: return loc.localized("training.stance.stand")
        case .crouch: return loc.localized("training.stance.crouch")
        case .jump: return loc.localized("training.stance.jump")
        }
    }

    private func guardLabel(_ guard: TrainingGuard) -> String {
        switch `guard` {
        case .noBlock: return loc.localized("training.guard.noBlock")
        case .allBlock: return loc.localized("training.guard.allBlock")
        case .randomBlock: return loc.localized("training.guard.randomBlock")
        case .firstHitBlock: return loc.localized("training.guard.firstHitBlock")
        }
    }

    private func wakeUpTechLabel(_ tech: TrainingWakeUpTech) -> String {
        switch tech {
        case .none: return loc.localized("training.wakeUp.none")
        case .quickRecovery: return loc.localized("training.wakeUp.quickRecovery")
        case .backRoll: return loc.localized("training.wakeUp.backRoll")
        }
    }
}

struct ReversalMovePickerSheet: View {
    @ObservedObject var viewModel: TrainingModeOverlayViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredMoves: [FightDataMove] {
        let moves = viewModel.availableMovesForReversal
        guard !searchText.isEmpty else { return moves }
        return moves.filter {
            ($0.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.input?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.localized("training.reversalAction.selectMove"))
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            TextField(loc.localized("training.reversalAction.search"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if filteredMoves.isEmpty {
                Text(loc.localized("training.reversalAction.noMoves"))
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredMoves) { move in
                            Button {
                                viewModel.selectReversalMove(move)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(move.name ?? move.input ?? "—")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppColors.textPrimary(colorScheme))
                                        .lineLimit(1)
                                    Spacer()
                                    if let input = move.input {
                                        Text(input)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(AppColors.textTertiary(colorScheme))
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(
                                    viewModel.reversalMoveId == move.id
                                    ? AppColors.brandAccent.opacity(0.15)
                                    : Color.clear
                                )
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: 320, height: 400)
        .background(AppColors.cardBackground(colorScheme))
    }
}

struct SequenceMovePickerSheet: View {
    @ObservedObject var viewModel: TrainingModeOverlayViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCharacterName: String?

    private var characters: [FightDataCharacter] {
        viewModel.manager.currentGameData?.characters ?? []
    }

    private var selectedCharacter: FightDataCharacter? {
        if let name = selectedCharacterName {
            return characters.first { $0.name == name }
        }
        return characters.first
    }

    private var currentMoves: [FightDataMove] {
        let char = selectedCharacter ?? characters.first
        return char?.moves.filter { $0.hasInputData } ?? []
    }

    private var filteredMoves: [FightDataMove] {
        guard !searchText.isEmpty else { return currentMoves }
        return currentMoves.filter {
            ($0.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.input?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.localized("training.addFMDMove"))
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            if characters.count > 1 {
                Picker(selection: $selectedCharacterName) {
                    ForEach(characters) { char in
                        Text(char.name).tag(Optional.some(char.name))
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            TextField(loc.localized("training.reversalAction.search"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if filteredMoves.isEmpty {
                Text(loc.localized("training.reversalAction.noMoves"))
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredMoves) { move in
                            Button {
                                let charName = selectedCharacterName ?? characters.first?.name ?? ""
                                viewModel.addFMDCard(move, characterName: charName)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(move.name ?? move.input ?? "—")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppColors.textPrimary(colorScheme))
                                        .lineLimit(1)
                                    Spacer()
                                    if let input = move.input {
                                        Text(input)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(AppColors.textTertiary(colorScheme))
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: 320, height: 400)
        .background(AppColors.cardBackground(colorScheme))
        .onAppear {
            if selectedCharacterName == nil {
                selectedCharacterName = characters.first?.name
            }
        }
    }
}

struct TrainingSequenceTab: View {
    @ObservedObject var viewModel: TrainingModeOverlayViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingMovePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            triggerSection
            frameProfileSection
            autoInvertSection
            cardListSection
        }
        .sheet(isPresented: $showingMovePicker) {
            SequenceMovePickerSheet(viewModel: viewModel)
                .gamepadDismissable { showingMovePicker = false }
        }
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.sequenceTrigger"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.sequenceTrigger) {
                ForEach(TrainingSequenceTrigger.allCases, id: \.self) { t in
                    Text(triggerLabel(t)).tag(t)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
        }
    }

    private var frameProfileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.frameProfile"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.frameProfile) {
                ForEach(FrameProfile.allCases, id: \.self) { p in
                    Text("\(p.rawValue)f").tag(p)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
        }
    }

    private var autoInvertSection: some View {
        Toggle(isOn: $viewModel.autoInvert) {
            Text(loc.localized("training.autoInvert"))
                .font(.subheadline)
                .foregroundColor(AppColors.textPrimary(colorScheme))
        }
    }

    private var cardListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(loc.localized("training.sequenceCards"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textPrimary(colorScheme))

                Spacer()

        Menu {
            Button(loc.localized("training.addFMDMove")) { showingMovePicker = true }
            Button(loc.localized("training.addDelay")) {
                viewModel.addSequenceCard(.delay(frames: 10))
            }
            Button(loc.localized("training.addTapeBlock")) {
                viewModel.addSequenceCard(.tape(slot: viewModel.activeTapeSlot))
            }
        } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(AppColors.brandAccent)
                }
                .menuStyle(.borderlessButton)
            }

            if viewModel.config.sequenceCards.isEmpty {
                Text(loc.localized("training.noCards"))
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(viewModel.config.sequenceCards) { card in
                    cardRow(card)
                }
            }
        }
    }

    private func cardRow(_ card: SequenceCard) -> some View {
        HStack {
            Image(systemName: cardIcon(card.cardType))
                .foregroundColor(AppColors.brandAccent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(cardLabel(card))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                if let detail = cardDetail(card) {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
            }

            Spacer()

            Button {
                if let index = viewModel.config.sequenceCards.firstIndex(where: { $0.id == card.id }) {
                    viewModel.removeSequenceCard(at: index)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(AppColors.cardBackground(colorScheme).opacity(0.5))
        .cornerRadius(6)
    }

    private func cardIcon(_ type: SequenceCardType) -> String {
        switch type {
        case .fmd: return "flame"
        case .delay: return "clock"
        case .tape: return "cassette.tape"
        }
    }

    private func cardLabel(_ card: SequenceCard) -> String {
        switch card.cardType {
        case .fmd: return card.fmdMoveName ?? "FMD"
        case .delay: return loc.localized("training.delayCard")
        case .tape: return "\(loc.localized("training.tapeCard")) \(card.tapeSlot + 1)"
        }
    }

    private func cardDetail(_ card: SequenceCard) -> String? {
        switch card.cardType {
        case .fmd: return card.fmdCharacterName
        case .delay: return "\(card.delayFrames)f"
        case .tape: return nil
        }
    }

    private func triggerLabel(_ trigger: TrainingSequenceTrigger) -> String {
        switch trigger {
        case .continuousLoop: return loc.localized("training.trigger.loop")
        case .onBlock: return loc.localized("training.trigger.onBlock")
        case .onHit: return loc.localized("training.trigger.onHit")
        }
    }
}

struct TrainingRecordingTab: View {
    @ObservedObject var viewModel: TrainingModeOverlayViewModel
    @ObservedObject private var tapeDeck: TapeDeck
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: TrainingModeOverlayViewModel) {
        self.viewModel = viewModel
        self.tapeDeck = viewModel.manager.tapeDeck
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            activeSlotSection
            slotGrid
            recordControls
        }
    }

    private var activeSlotSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.activeTapeSlot"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.activeTapeSlot) {
                ForEach(0..<TapeDeck.maxSlots, id: \.self) { i in
                    Text(loc.localized("training.tapeSlot") + " \(i + 1)").tag(i)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
        }
    }

    private var slotGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.tapeSlots"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            ForEach(0..<TapeDeck.maxSlots, id: \.self) { slot in
                HStack {
                    Image(systemName: tapeDeck.slots[slot] != nil ? "cassette.tape.fill" : "cassette.tape")
                        .foregroundColor(tapeDeck.slots[slot] != nil ? AppColors.brandAccent : AppColors.textTertiary(colorScheme))

                    Text(tapeDeck.slots[slot] != nil
                         ? "\(tapeDeck.slots[slot]!.frames.count)f"
                         : loc.localized("training.emptySlot"))
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textPrimary(colorScheme))

                    Spacer()

                    if tapeDeck.slots[slot] != nil {
                        Button {
                            viewModel.clearTapeSlot(slot)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(AppColors.cardBackground(colorScheme).opacity(0.5))
                .cornerRadius(6)
            }
        }
    }

    private var recordControls: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleRecording()
            } label: {
                Label(
                    tapeDeck.isRecording ? loc.localized("training.stopRecording") :
                    tapeDeck.isCountingDown ? loc.localized("training.cancelCountdown") :
                    loc.localized("training.startRecording"),
                    systemImage: tapeDeck.isRecording ? "stop.circle.fill" : "record.circle"
                )
                .foregroundColor(tapeDeck.isRecording || tapeDeck.isCountingDown ? .red : AppColors.brandAccent)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if tapeDeck.isCountingDown {
                Text("3…2…1")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.orange)
            } else if tapeDeck.isRecording {
                Text("\(tapeDeck.recordFrameCount)f")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }
        }
    }
}

struct TrainingSettingsTab: View {
    @ObservedObject var viewModel: TrainingModeOverlayViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var buttonDisplayMode: ButtonDisplayMode = ButtonDisplayMode.current
    @State private var showMoveNames: Bool = AppSettings.getBool("moveListShowMoveNames", defaultValue: false)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            resetPositionSection
            overlayPositionSection
            healthRegenSection
            superMeterSection
            hotkeySection
            buttonDisplaySection
        }
    }

    private var buttonDisplaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("settings.moveList.display"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Toggle(loc.localized("settings.moveList.showMoveNames"), isOn: $showMoveNames)
                .onChange(of: showMoveNames) { _, newValue in
                    AppSettings.setBool("moveListShowMoveNames", value: newValue)
                    viewModel.onMoveListSettingsChanged?()
                }

            Picker(loc.localized("settings.moveList.buttonDisplayMode"), selection: $buttonDisplayMode) {
                Text(loc.localized("settings.moveList.buttonDisplay.symbol"))
                    .tag(ButtonDisplayMode.symbol)
                Text(loc.localized("settings.moveList.buttonDisplay.consoleButton"))
                    .tag(ButtonDisplayMode.consoleButton)
                Text(loc.localized("settings.moveList.buttonDisplay.inputKey"))
                    .tag(ButtonDisplayMode.inputKey)
            }
            .pickerStyle(.menu)
            .tint(AppColors.brandAccent)
            .onChange(of: buttonDisplayMode) { _, newValue in
                AppSettings.set(ButtonDisplayMode.settingsKey, value: newValue.rawValue)
                viewModel.onMoveListSettingsChanged?()
            }
            Text(loc.localized("settings.moveList.buttonDisplayModeDesc"))
                .font(.caption)
                .foregroundColor(AppColors.textTertiary(colorScheme))
        }
    }

    private var resetPositionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.resetPosition"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.resetPosition) {
                ForEach(TrainingResetPosition.allCases, id: \.self) { r in
                    Text(resetLabel(r)).tag(r)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)

        HStack(spacing: 8) {
            Button {
                viewModel.performReset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                Text(loc.localized("training.resetNow"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if viewModel.resetPosition == .custom
                || viewModel.resetPosition == .leftCorner
                || viewModel.resetPosition == .rightCorner {
                Button {
                    if viewModel.resetPosition == .custom {
                        viewModel.saveResetPoint()
                    } else {
                        viewModel.saveCornerResetPoint()
                    }
                } label: {
                    Image(systemName: "bookmark.fill")
                    Text(loc.localized("training.savePoint"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        }
    }

    private var healthRegenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.healthRegen"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.healthRegen) {
                ForEach(TrainingHealthRegen.allCases, id: \.self) { r in
                    Text(healthRegenLabel(r)).tag(r)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
        }
    }

    private var superMeterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.superMeter"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Picker(selection: $viewModel.superMeter) {
                ForEach(TrainingSuperMeter.allCases, id: \.self) { m in
                    Text(meterLabel(m)).tag(m)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
        }
    }

    private func healthRegenLabel(_ regen: TrainingHealthRegen) -> String {
        switch regen {
        case .instantRefill: return loc.localized("training.regen.instant")
        case .linearRegen: return loc.localized("training.regen.linear")
        case .normal: return loc.localized("training.regen.normal")
        }
    }

    private func meterLabel(_ meter: TrainingSuperMeter) -> String {
        switch meter {
        case .alwaysMaxed: return loc.localized("training.meter.maxed")
        case .keepCurrent: return loc.localized("training.meter.keep")
        case .empty: return loc.localized("training.meter.empty")
        }
    }

    private func resetLabel(_ reset: TrainingResetPosition) -> String {
        switch reset {
        case .roundStart: return loc.localized("training.reset.roundStart")
        case .leftCorner: return loc.localized("training.reset.leftCorner")
        case .rightCorner: return loc.localized("training.reset.rightCorner")
        case .custom: return loc.localized("training.reset.custom")
        }
    }

    private var overlayPositionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.overlayPosition"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Button {
                viewModel.onResetOverlayPosition?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text(loc.localized("training.resetOverlayPosition"))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.hotkeys"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            VStack(alignment: .leading, spacing: 3) {
                hotkeyRow(loc.localized("training.hotkeys.reset"))
                hotkeyRow(loc.localized("training.hotkeys.record"))
                hotkeyRow(loc.localized("training.hotkeys.playback"))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(AppColors.cardBackground(colorScheme).opacity(0.5))
            .cornerRadius(6)
        }
    }

    private func hotkeyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
    }
}

struct TrainingDisplayTab: View {
    @ObservedObject var viewModel: TrainingModeOverlayViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var sequenceRunner = TrainingModeManager.shared.sequenceRunner
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputHistorySection
            fmdMonitorSection
            frameAdvantageSection
        }
    }

    private var inputHistorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.inputDisplay"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            if viewModel.p1InputHistory.isEmpty {
                Text(loc.localized("training.inputDisplay.noData"))
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.p1InputHistory.suffix(8).reversed()) { entry in
                        inputHistoryRow(entry)
                    }
                }
                .padding(8)
                .background(AppColors.cardBackground(colorScheme).opacity(0.5))
                .cornerRadius(6)
            }
        }
    }

    private func inputHistoryRow(_ entry: TrainingModeOverlayViewModel.InputHistoryEntry) -> some View {
        let dirTokens = retroButtonsToDirectionTokens(entry.directions)
        let btnTokens = retroButtonsToButtonTokens(entry.buttons, manager: viewModel.manager)

        return HStack(spacing: NotationMetrics.tokenSpacing) {
            Text("\(entry.frameIndex)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(AppColors.textTertiary(colorScheme))
                .frame(width: 24, alignment: .trailing)

            ForEach(Array(dirTokens.enumerated()), id: \.offset) { _, token in
                MoveNotationTokenView(token: token, isHighlighted: true, compact: true)
            }

            ForEach(Array(btnTokens.enumerated()), id: \.offset) { _, token in
                MoveNotationTokenView(token: token, isHighlighted: true, compact: true)
            }

            Spacer()
        }
        .frame(height: 18)
    }

    private func retroButtonsToDirectionTokens(_ buttons: Set<RetroButton>) -> [NotationToken] {
        guard let dir = FightDataDirection.fromRetroButtons(held: buttons) else { return [] }
        return [.direction(dir)]
    }

    private func retroButtonsToButtonTokens(_ buttons: Set<RetroButton>, manager: TrainingModeManager) -> [NotationToken] {
        let nonDirButtons = buttons.filter { !$0.isDirectional }
        guard !nonDirButtons.isEmpty else { return [] }

        let gameData = manager.currentGameData
        let layout = manager.currentArcadeLayout
        let systemID = manager.currentSystemID
        let sysCtrlMap = gameData?.systemControlMappings
        let displayMode = ButtonDisplayMode.current

        var tokens: [NotationToken] = []
        let sorted = nonDirButtons.sorted(by: { $0.rawValue < $1.rawValue })
        var first = true
        for btn in sorted {
            guard let fdKey = ArcadeButtonMapper.shared.fightDataKey(for: btn, layout: layout, systemID: systemID, systemControlMappings: sysCtrlMap) else { continue }
            if !first { tokens.append(.separator) }
            first = false
            let btnType = MoveNotationRenderer.resolveButtonType(fdKey, gameData: gameData)
            switch displayMode {
            case .symbol:
                tokens.append(.button(btnType))
            case .consoleButton:
                tokens.append(.buttonKeyLabel(btnType, keyLabel: btn.rawValue.uppercased()))
            case .inputKey:
                if let kl = ButtonKeyResolver.keyLabel(for: fdKey, systemID: systemID, layout: layout, systemControlMappings: sysCtrlMap) {
                    tokens.append(.buttonKeyLabel(btnType, keyLabel: kl))
                } else {
                    tokens.append(.button(btnType))
                }
            }
        }
        return tokens
    }

    private var fmdMonitorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.fmdMonitor"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            if sequenceRunner.isExecuting, let name = sequenceRunner.activeFMDMoveName {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppColors.brandAccent)
                        .lineLimit(1)

                    if sequenceRunner.activeFMDTotalFrames > 0 {
                        ProgressView(value: Double(sequenceRunner.activeFMDFrame), total: Double(sequenceRunner.activeFMDTotalFrames))
                            .progressViewStyle(.linear)
                            .tint(AppColors.brandAccent)

                        Text("Frame \(sequenceRunner.activeFMDFrame + 1)/\(sequenceRunner.activeFMDTotalFrames)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(AppColors.brandAccent.opacity(0.1))
                .cornerRadius(4)
            } else if sequenceRunner.waitingForTrigger {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text(loc.localized("training.fmdMonitor.waiting"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
            } else {
                Text(loc.localized("training.fmdMonitor.idle"))
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
            }
        }
    }

    private var frameAdvantageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("training.frameAdvantage"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary(colorScheme))

            Text(loc.localized("training.frameAdvantage.comingSoon"))
                .font(.caption)
                .foregroundColor(AppColors.textTertiary(colorScheme))
        }
    }
}

struct TrainingMovesTab: View {
    @ObservedObject var viewModel: TrainingModeOverlayViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let game = viewModel.manager.currentGameData {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(game.characters, id: \.name) { character in
                        characterRow(character)
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "questionmark.folder")
                    .font(.title2)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
                Text(loc.localized("training.noGameData"))
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func characterRow(_ character: FightDataCharacter) -> some View {
        let isExpanded = viewModel.expandedCharacterId == character.id
        let isEnabled = viewModel.enabledCharacterName == character.name

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isEnabled ? AppColors.brandAccent : AppColors.textSecondaryNeutral(colorScheme))

                Text(character.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isEnabled ? AppColors.brandAccent : AppColors.textPrimary(colorScheme))

                Spacer()

                if isEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.brandAccent)
                }

                let sections = viewModel.sectionsForCharacter(character)
                let enabledCount = sections.filter { viewModel.isSectionEnabled(characterName: character.name, section: $0) }.count
                if enabledCount < sections.count && !isEnabled {
                    Text(verbatim: "\(enabledCount)/\(sections.count)")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.toggleExpandCharacter(character)
                    }
                } label: {
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
                .allowsHitTesting(true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectCharacterAndShowMoves(character)
            }
            .background(isEnabled ? AppColors.brandAccent.opacity(0.15) : AppColors.cardBackground(colorScheme).opacity(0.3))
            .cornerRadius(6)

            if isExpanded {
                characterSectionsView(character)
                    .padding(.leading, 20)
                    .padding(.top, 2)
            }
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
                            .foregroundColor(isEnabled ? AppColors.textPrimary(colorScheme) : AppColors.textTertiary(colorScheme))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(AppColors.brandAccent)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.enableAllSections(characterName: character.name, sections: sections)
                } label: {
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

                Button {
                    viewModel.disableAllSections(characterName: character.name, sections: sections)
                } label: {
                    Text(loc.localized("movelist.disableAll"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    viewModel.selectCharacterAndShowMoves(character)
                } label: {
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
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - P2 Join Status Overlay (shown on game window during P2 join)

struct P2JoinStatusOverlay: View {
    let frameDriver: TrainingFramePollDriver
    let isArcadeSystem: Bool
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: Int = 0
    @State private var frame: Int = 0
    @State private var maxFrames: Int = 0
    @State private var timer: Timer?

    private let pollInterval: TimeInterval = 0.1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.8)
                    .controlSize(.small)
                Text(loc.localized("training.p2Join.joining"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)

            Text(phaseText)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))

            if maxFrames > 0 {
                ProgressView(value: min(Double(frame) / Double(maxFrames), 1.0))
                    .tint(.white)
                    .progressViewStyle(.linear)
                    .frame(width: 160)
            } else {
                ProgressView()
                    .scaleEffect(0.6)
                    .progressViewStyle(.circular)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 20)
        .padding(.top, 60)
        .onAppear(perform: startPolling)
        .onDisappear(perform: stopPolling)
    }

    private var phaseText: String {
        if isArcadeSystem {
            switch phase {
            case 1: return loc.localized("training.p2Join.insertingCoin")
            case 2: return loc.localized("training.p2Join.coinReleased")
            case 3: return loc.localized("training.p2Join.pressingStart")
            case 4: return loc.localized("training.p2Join.waitingCharSelect")
            case 5: return loc.localized("training.p2Join.selectingCharacter")
            default: return ""
            }
        } else {
            switch phase {
            case 1: return loc.localized("training.p2Join.pressingStart")
            case 2: return loc.localized("training.p2Join.waitingCharSelect")
            case 3: return loc.localized("training.p2Join.selectingCharacter")
            default: return ""
            }
        }
    }

    private func startPolling() {
        phase = frameDriver.currentP2JoinPhase
        frame = frameDriver.currentP2JoinFrame
        maxFrames = frameDriver.p2JoinMaxFramesForCurrentPhase
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
            Task { @MainActor in
                phase = frameDriver.currentP2JoinPhase
                frame = frameDriver.currentP2JoinFrame
                maxFrames = frameDriver.p2JoinMaxFramesForCurrentPhase
            }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
