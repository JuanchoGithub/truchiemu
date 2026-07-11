import SwiftUI
import AppKit

struct MoveEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var storageService = MoveListStorageService.shared
    private let moveListService = MoveListService.shared

    let gameName: String
    let characterName: String
    let editingMove: FightDataMove?
    let isCustom: Bool
    let gameCategories: [String: String]
    let fightDataGame: FightDataGame?
    let onSave: (FightDataMove) -> Void
    let onDelete: (() -> Void)?
    let onBack: (() -> Void)?

    @State private var moveName: String
    @State private var moveCategory: String
    @State private var steps: [EditorStep]
    @State private var moveHitLevels: String
    @State private var moveCondition: String
    @State private var selectedStepIndex: Int? = nil
    @State private var showCategoryPicker = false
    @State private var customCategoryText: String = ""

    init(
        gameName: String,
        characterName: String,
        editingMove: FightDataMove?,
        isCustom: Bool,
        gameCategories: [String: String],
        fightDataGame: FightDataGame? = nil,
        onSave: @escaping (FightDataMove) -> Void,
        onDelete: (() -> Void)?,
        onBack: (() -> Void)? = nil
    ) {
        self.gameName = gameName
        self.characterName = characterName
        self.editingMove = editingMove
        self.isCustom = isCustom
        self.gameCategories = gameCategories
        self.fightDataGame = fightDataGame
        self.onSave = onSave
        self.onDelete = onDelete
        self.onBack = onBack

        _moveName = State(initialValue: editingMove?.name ?? "")
        _moveCategory = State(initialValue: editingMove?.category ?? "_@special")
        _moveHitLevels = State(initialValue: editingMove?.hitLevels ?? "")
        _moveCondition = State(initialValue: editingMove?.condition ?? "")

        var preSteps: [EditorStep] = []
        if let move = editingMove {
            let parsed = InputParser.parse(move.input ?? "")
            for (seqIdx, sequence) in parsed.enumerated() {
                if seqIdx > 0 { preSteps.append(EditorStep(isBranch: true)) }
            var pendingAir = false
            for step in sequence {
                if step.isAirStep {
                    pendingAir = true
                    continue
                }
                    var es = EditorStep()
                    es.isAir = pendingAir
                    pendingAir = false
                    es.direction = step.direction
                    es.buttons = step.buttons
                    es.isCharge = step.isCharge
                    es.isRapid = step.isRapid
                    preSteps.append(es)
                }
            }
        }
        _steps = State(initialValue: preSteps)
    }

    private var editorTitle: String {
        "\(gameName) > \(characterName)"
    }

    struct EditorStep: Identifiable {
        let id = UUID()
        var direction: Int? = nil
        var buttons: [String] = []
        var isCharge: Bool = false
        var isNeutral: Bool = false
        var isRapid: Bool = false
        var isAir: Bool = false
        var isBranch: Bool = false

        var isEmpty: Bool { direction == nil && buttons.isEmpty && !isBranch }
    }

    struct EditorButton: Identifiable {
        let id = UUID()
        let key: String
        let label: String
        var isSelected: Bool = false
    }

    private static let fallbackCapcomButtons: [EditorButton] = [
        EditorButton(key: "^E", label: "LP"),
        EditorButton(key: "^F", label: "MP"),
        EditorButton(key: "^G", label: "HP"),
        EditorButton(key: "^H", label: "LK"),
        EditorButton(key: "^I", label: "MK"),
        EditorButton(key: "^J", label: "HK"),
    ]

    private static let universalButtons: [(key: String, label: String)] = [
        ("_S", "Start"), ("_O", "Charge"), ("_X", "Close"), ("_G", "Guard"),
    ]

    static func gameSpecificButtons(from game: FightDataGame?) -> [EditorButton] {
        guard let game else { return fallbackCapcomButtons }
        let controls = game.controls
        let abbr = game.controlAbbr ?? [:]
        let groups = game.controlGroups ?? [:]

        var buttons: [EditorButton] = []
        var seen = Set<String>()

        func addKey(_ key: String) {
            guard !seen.contains(key) else { return }
            seen.insert(key)
            let label = controls[key] ?? abbr[key] ?? key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: "")
            buttons.append(EditorButton(key: key, label: label))
        }

        for groupKey in ["_P", "_K", "_W"] {
            if let members = groups[groupKey] {
                for member in members { addKey(member) }
                addKey(groupKey)
            }
        }

        for key in controls.keys.sorted() {
            guard !key.hasPrefix("_@") else { continue }
            addKey(key)
        }
        for key in abbr.keys.sorted() {
            guard !key.hasPrefix("_@") else { continue }
            addKey(key)
        }

        if buttons.isEmpty { return fallbackCapcomButtons }
        return buttons
    }

    static func buildFullButtonCatalog(from game: FightDataGame?) -> [(key: String, label: String)] {
        var entries: [(key: String, label: String)] = []
        var seen = Set<String>()

        func addEntry(_ key: String, _ label: String) {
            guard !seen.contains(key) else { return }
            seen.insert(key)
            entries.append((key: key, label: label))
        }

        for btn in gameSpecificButtons(from: game) {
            addEntry(btn.key, btn.label)
        }

        let controls = game?.controls ?? [:]
        let abbr = game?.controlAbbr ?? [:]
        for (key, label) in universalButtons {
            addEntry(key, label)
        }
        for key in controls.keys.sorted() {
            guard !key.hasPrefix("_@") else { continue }
            addEntry(key, controls[key]!)
        }
        for key in abbr.keys.sorted() {
            guard !key.hasPrefix("_@") else { continue }
            let full = controls[key] ?? abbr[key]!
            addEntry(key, full)
        }

        let fallbackKeys: [(key: String, label: String)] = [
            ("^E", "LP"), ("^F", "MP"), ("^G", "HP"),
            ("^H", "LK"), ("^I", "MK"), ("^J", "HK"),
            ("_A", "A"), ("_B", "B"), ("_C", "C"), ("_D", "D"),
            ("_P", "Punch"), ("_K", "Kick"), ("_H", "Hover"),
            ("^W", "W"), ("^V", "V"), ("^U", "U"), ("^T", "T"), ("^M", "M"),
        ]
        let hasGameControls = !(game?.controls ?? [:]).isEmpty
        if !hasGameControls {
            for (key, label) in fallbackKeys {
                addEntry(key, label)
            }
        }

        return entries
    }

    private static let standardCategories: [(key: String, label: String)] = [
        ("_@special", "Special"), ("_@super", "Super"), ("_@command", "Command Normal"),
        ("_@normal", "Normal"), ("_@target", "Target Combo"), ("_@chain", "Chain"),
        ("_@throw", "Throw"), ("_@move", "Movement"), ("_@taunt", "Taunt"),
    ]

    private func fightDataDirection(from intVal: Int) -> FightDataDirection? {
        FightDataDirection(rawValue: intVal)
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: 4) {
                Button(action: { onBack?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text(loc.localized("movelist.back"))
                            .font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.brandAccent)
                Spacer()
                Text(editorTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                Spacer()
            }

            moveInfoSection
                .padding(AppSpacing.md)
                .background(AppColors.cardBackground(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))

            HStack(alignment: .top, spacing: AppSpacing.md) {
                directionPadSection
                    .padding(AppSpacing.md)
                    .background(AppColors.cardBackground(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))

                buttonPaletteSection
                    .padding(AppSpacing.md)
                    .background(AppColors.cardBackground(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            }

            modifierSection

            compressedPreviewRow

            stepListSection
                .frame(maxHeight: .infinity)
                .padding(AppSpacing.md)
                .background(AppColors.cardBackground(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))

            Divider()
            actionButtons
        }
        .padding(AppSpacing.lg)
    }

    // MARK: - Move Info

    private var moveInfoSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            TextField(loc.localized("settings.moveList.editor.moveName"), text: $moveName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text(loc.localized("settings.moveList.editor.category"))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button(action: { showCategoryPicker = true }) {
                    HStack(spacing: 4) {
                        Text(categoryDisplayName)
                            .font(.system(size: 13))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showCategoryPicker) {
                    categoryPickerContent
                        .gamepadDismissable { showCategoryPicker = false }
                }
            }
        }
    }

    private var categoryDisplayName: String {
        if let gameLabel = gameCategories[moveCategory] {
            return gameLabel
        }
        if let standard = Self.standardCategories.first(where: { $0.key == moveCategory }) {
            return standard.label
        }
        let stripped = moveCategory.replacingOccurrences(of: "_", with: "")
        if let gameLabel = gameCategories[stripped] {
            return gameLabel
        }
        if moveCategory.hasPrefix("_@") { return String(moveCategory.dropFirst(2)) }
        return stripped
    }

    private var gameCategoryEntries: [(key: String, label: String)] {
        gameCategories.map { (key: $0.key, label: $0.value) }
            .sorted { $0.key < $1.key }
    }

    private var categoryPickerContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(loc.localized("settings.moveList.editor.category"))
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, AppSpacing.sm)

            if !gameCategoryEntries.isEmpty {
                ForEach(gameCategoryEntries, id: \.key) { cat in
                    Button(action: {
                        moveCategory = cat.key
                        showCategoryPicker = false
                    }) {
                        HStack {
                            Text(cat.label)
                                .font(.system(size: 13))
                            if cat.key == moveCategory {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.brandAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                }

                Divider()
            }

            ForEach(Self.standardCategories, id: \.key) { cat in
                Button(action: {
                    moveCategory = cat.key
                    showCategoryPicker = false
                }) {
                    HStack {
                        Text(cat.label)
                            .font(.system(size: 13))
                        if cat.key == moveCategory {
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppColors.brandAccent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
            }

            Divider()

            HStack {
                TextField(loc.localized("settings.moveList.editor.customCategory"), text: $customCategoryText)
                    .textFieldStyle(.roundedBorder)
                Button(loc.localized("movelist.ok")) {
                    if !customCategoryText.isEmpty {
                        moveCategory = "_@\(customCategoryText.lowercased())"
                        customCategoryText = ""
                        showCategoryPicker = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(customCategoryText.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, AppSpacing.sm)
        }
        .frame(width: 250)
    }

    // MARK: - Compressed Preview

    @ViewBuilder
    private var compressedPreviewRow: some View {
        let branches = splitStepsByBranches()
        if !branches.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Preview")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                ScrollView(.horizontal, showsIndicators: false) {
                    if let (dirTokens, btnTokens) = detectCrossProduct(branches) {
                        HStack(spacing: NotationMetrics.tokenSpacing) {
                            Text("(").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                            ForEach(Array(dirTokens.enumerated()), id: \.offset) { idx, tokens in
                                if idx > 0 {
                                    Text("|").font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                                }
                                MoveNotationTokenRow(tokens: tokens, compact: true)
                            }
                            Text(")").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                            Text("+").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.textTertiary(colorScheme))
                            Text("(").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                            ForEach(Array(btnTokens.enumerated()), id: \.offset) { idx, tokens in
                                if idx > 0 {
                                    Text("|").font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                                }
                                MoveNotationTokenRow(tokens: tokens, compact: true)
                            }
                            Text(")").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack(spacing: NotationMetrics.tokenSpacing) {
                            Text("(").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                            ForEach(Array(branches.enumerated()), id: \.offset) { idx, indices in
                                if idx > 0 {
                                    Text("|").font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                                }
                                branchTokensView(indices)
                            }
                            Text(")").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(AppColors.cardBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xs)
                    .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
            )
        }
    }

    private func branchTokensView(_ indices: [Int]) -> some View {
        var tokens: [NotationToken] = []
        for stepIndex in indices {
            tokens.append(contentsOf: buildStepTokens(steps[stepIndex]))
        }
        return MoveNotationTokenRow(tokens: tokens, compact: false)
    }

    private func detectCrossProduct(_ branches: [[Int]]) -> ([[NotationToken]], [[NotationToken]])? {
        guard branches.count > 1 else { return nil }
        let allSingle = branches.allSatisfy { indices -> Bool in
            guard indices.count == 1 else { return false }
            let step = steps[indices[0]]
            return step.direction != nil && !step.buttons.isEmpty && !step.isCharge && !step.isNeutral
        }
        guard allSingle else { return nil }

        var dirs: [Int] = []
        var allBtns: [[String]] = []
        for indices in branches {
            let step = steps[indices[0]]
            if let d = step.direction, !dirs.contains(d) { dirs.append(d) }
            if !allBtns.contains(step.buttons) { allBtns.append(step.buttons) }
        }

        guard dirs.count * allBtns.count == branches.count else { return nil }

        let dirTokens = dirs.compactMap { d -> [NotationToken]? in
            guard let fd = FightDataDirection(rawValue: d) else { return nil }
            return [.direction(fd)]
        }
        let btnTokens = allBtns.map { btns -> [NotationToken] in
            var toks: [NotationToken] = []
            for (i, k) in btns.enumerated() {
                if i > 0 { toks.append(.separator) }
                toks.append(.button(MoveNotationRenderer.resolveButtonType(k, gameData: fightDataGame ?? moveListService.currentGameData)))
            }
            return toks
        }

        guard dirTokens.count == dirs.count else { return nil }
        return (dirTokens, btnTokens)
    }



    // MARK: - Direction Pad

    private var directionPadSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label(loc.localized("settings.moveList.editor.directions"), systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            let gridSize: CGFloat = 30
            let spacing: CGFloat = 3
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach([7, 8, 9, 4, 5, 6, 1, 2, 3], id: \.self) { dir in
                        Button(action: { addDirectionStep(dir) }) {
                            Image("NotationDir\(dir)")
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(dir == 5 ? 8 : 4)
                                .frame(width: gridSize, height: gridSize)
                                .foregroundStyle(.white)
                                .background(AppColors.cardBackground(colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.xs)
                                        .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Button Palette

    private var buttonPaletteSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Label(loc.localized("settings.moveList.editor.buttons"), systemImage: "hand.point.up.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            FlowLayout(spacing: 4) {
                ForEach(Self.buildFullButtonCatalog(from: fightDataGame), id: \.key) { catBtn in
                    Button(action: { addButtonStep(catBtn.key) }) {
                        VStack(spacing: 1) {
                            MoveNotationTokenView(
                                token: buttonTokenForCatalog(key: catBtn.key, label: catBtn.label),
                                isHighlighted: true,
                                compact: true
                            )
                            Text(catBtn.label)
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 40)
                        }
                        .frame(width: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func buttonTokenForCatalog(key: String, label: String) -> NotationToken {
        let cd = rendererControlData
        return MoveNotationRenderer.mapButtonToToken(
            key,
            controls: cd.controls,
            controlAbbr: cd.controlAbbr,
            controlGroups: cd.controlGroups
        )
    }

    // MARK: - Modifiers

    private var modifierSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label(loc.localized("settings.moveList.editor.modifiers"), systemImage: "gearshape.2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            HStack(spacing: AppSpacing.sm) {
                if let idx = selectedStepIndex, idx < steps.count {
                    Toggle(isOn: Binding(
                        get: { steps[idx].isCharge },
                        set: { steps[idx].isCharge = $0 }
                    )) {
                        Label("⏳ Charge", systemImage: "hourglass")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                    Toggle(isOn: Binding(
                        get: { steps[idx].isNeutral },
                        set: { steps[idx].isNeutral = $0 }
                    )) {
                        Label("N Neut", systemImage: "scope")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                    Toggle(isOn: Binding(
                        get: { steps[idx].isRapid },
                        set: { steps[idx].isRapid = $0 }
                    )) {
                        Label("⚡ Rapid", systemImage: "bolt")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                } else {
                    Text(loc.localized("settings.moveList.editor.selectStepHint"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }

                Spacer(minLength: 4)

                Button(action: { addBranchStep() }) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(loc.localized("settings.moveList.editor.addBranch"))
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Step List

    private var stepListSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Label(loc.localized("settings.moveList.editor.sequence"), systemImage: "list.number")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                Spacer()
                if !steps.isEmpty {
                    Button(action: { steps.removeAll(); selectedStepIndex = nil }) {
                        Text(loc.localized("settings.moveList.editor.clearAll"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            if steps.isEmpty {
                Text(loc.localized("settings.moveList.editor.emptySequence"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(AppSpacing.md)
            } else {
                let branches = splitStepsByBranches()
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(Array(branches.enumerated()), id: \.offset) { branchIdx, branchIndices in
                            if branchIdx > 0 {
                                Text("|").font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: NotationMetrics.tokenSpacing) {
                                    ForEach(branchIndices, id: \.self) { index in
                                        stepTokensInline(step: steps[index], index: index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func splitStepsByBranches() -> [[Int]] {
        var branches: [[Int]] = [[]]
        for (index, step) in steps.enumerated() {
            if step.isBranch {
                branches.append([])
            } else {
                branches[branches.count - 1].append(index)
            }
        }
        return branches.filter { !$0.isEmpty }
    }

    private func stepTokensInline(step: EditorStep, index: Int) -> some View {
        let isSelected = selectedStepIndex == index
        let tokens = buildStepTokens(step)

        if tokens.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            Button(action: { selectedStepIndex = isSelected ? nil : index }) {
                HStack(spacing: 1) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                        MoveNotationTokenView(token: token, isHighlighted: true)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, isSelected ? 2 : 0)
                .background(isSelected ? AppColors.brandAccent.opacity(0.15) : Color.clear)
                .cornerRadius(3)
                .overlay(
                    isSelected ? RoundedRectangle(cornerRadius: 3)
                        .stroke(AppColors.brandAccent, lineWidth: 1) : nil
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    if index < steps.count { steps[index].isCharge.toggle() }
                } label: {
                    Label(loc.localized("settings.moveList.editor.toggleCharge"), systemImage: "hourglass")
                }
                Button {
                    if index < steps.count { steps[index].isNeutral.toggle() }
                } label: {
                    Label(loc.localized("settings.moveList.editor.toggleNeutral"), systemImage: "scope")
                }
                Button {
                    if index < steps.count { steps[index].isRapid.toggle() }
                } label: {
                    Label(loc.localized("settings.moveList.editor.toggleRapid"), systemImage: "bolt")
                }
                Divider()
                Button(role: .destructive) {
                    steps.remove(at: index)
                    if selectedStepIndex == index { selectedStepIndex = nil }
                    else if let si = selectedStepIndex, si > index { selectedStepIndex = si - 1 }
                } label: {
                    Label(loc.localized("settings.moveList.editor.deleteStep"), systemImage: "trash")
                }
            }
        )
    }

    private var rendererControlData: (controls: [String: String], controlAbbr: [String: String], controlGroups: [String: [String]]) {
        let gd = fightDataGame ?? moveListService.currentGameData
        return (
            gd?.controls ?? [:],
            gd?.controlAbbr ?? [:],
            gd?.controlGroups ?? [:]
        )
    }

    private func buildStepTokens(_ step: EditorStep) -> [NotationToken] {
        if step.isBranch { return [.alternative] }
        if step.isNeutral { return [.direction(.neutral)] }
        let ps = ParsedStep(
            direction: step.direction,
            buttons: step.buttons,
            isCharge: step.isCharge,
            isHold: false,
            isRelease: false,
            isRapid: step.isRapid,
            isAirStep: step.isAir,
            isMotion360: false,
            isCloseRange: false
        )
        let cd = rendererControlData
        return MoveNotationRenderer.renderSteps([[ps]], controls: cd.controls, controlAbbr: cd.controlAbbr, controlGroups: cd.controlGroups)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack {
            if let onDelete {
                Button(loc.localized("settings.moveList.editor.delete"), role: .destructive, action: { onDelete() })
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button(loc.localized("movelist.cancel")) { onBack?() }
                .buttonStyle(.bordered)
            Button(loc.localized("settings.moveList.editor.save")) { saveMove() }
                .buttonStyle(.borderedProminent)
                .disabled(moveName.isEmpty || steps.isEmpty)
        }
    }

    // MARK: - Actions

    private func addDirectionStep(_ dir: Int) {
        if let idx = selectedStepIndex, idx < steps.count, steps[idx].direction == nil {
            steps[idx].direction = dir
            selectedStepIndex = nil
        } else {
            steps.append(EditorStep(direction: dir))
            selectedStepIndex = nil
        }
    }

    private func addBranchStep() {
        if let idx = selectedStepIndex, idx < steps.count {
            steps.insert(EditorStep(isBranch: true), at: idx + 1)
        } else {
            steps.append(EditorStep(isBranch: true))
        }
        selectedStepIndex = nil
    }

    private func addButtonStep(_ key: String) {
        if let idx = selectedStepIndex, idx < steps.count {
            if !steps[idx].buttons.contains(key) {
                steps[idx].buttons.append(key)
            }
            selectedStepIndex = nil
        } else {
            steps.append(EditorStep(buttons: [key]))
            selectedStepIndex = nil
        }
    }

    private func saveMove() {
        let rawInput = buildRawInput()
        let hl = moveHitLevels.isEmpty ? nil : moveHitLevels
        let cond = moveCondition.isEmpty ? nil : moveCondition

        let move = FightDataMove(
            category: moveCategory,
            name: moveName,
            input: rawInput,
            hitLevels: hl,
            condition: cond
        )

        onSave(move)
        onBack?()
    }

    private func buildRawInput() -> String {
        var branches: [[String]] = [[]]
        for step in steps {
            if step.isBranch {
                branches.append([])
                continue
            }
            var current = branches[branches.count - 1]
            if step.isNeutral {
                current.append("_5")
            } else if let dir = step.direction {
                var s = step.isAir ? "_^_" : "_"
                if step.isCharge { s = "_O_" }
                s += "\(dir)"
                if !step.buttons.isEmpty {
                    let btns = step.buttons.map { $0.hasPrefix("^") || $0.hasPrefix("_") ? $0 : "_\($0)" }.joined()
                    s += "_+" + btns
                }
                if step.isRapid { s += "^*" }
                current.append(s)
            } else if !step.buttons.isEmpty {
                var s = step.isAir ? "_^" : ""
                s += step.buttons.map { $0.hasPrefix("^") || $0.hasPrefix("_") ? $0 : "_\($0)" }.joined()
                if step.isRapid { s += "^*" }
                current.append(s)
        } else if step.isRapid {
            current.append("^*")
            }
            branches[branches.count - 1] = current
        }
        return branches.map { $0.joined(separator: " ") }.joined(separator: " / ")
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        totalHeight = y + rowHeight
        return ArrangeResult(size: CGSize(width: maxWidth == .infinity ? x : maxWidth, height: totalHeight), positions: positions)
    }
}
