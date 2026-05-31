import SwiftUI
import AppKit

struct MoveEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var storageService = MoveListStorageService.shared

    let gameName: String
    let characterName: String
    let editingMove: FightDataMove?
    let isCustom: Bool
    let gameCategories: [String: String]
    let onSave: (FightDataMove) -> Void
    let onDelete: (() -> Void)?

    @State private var moveName: String
    @State private var moveCategory: String
    @State private var steps: [EditorStep]
    @State private var moveHitLevels: String
    @State private var moveCondition: String
    @State private var selectedStepIndex: Int? = nil
    @State private var showCategoryPicker = false
    @State private var customCategoryText: String = ""

    @State private var availableButtons: [EditorButton] = MoveEditorView.defaultCapcomButtons
    @State private var showButtonCatalog = false

    init(
        gameName: String,
        characterName: String,
        editingMove: FightDataMove?,
        isCustom: Bool,
        gameCategories: [String: String],
        onSave: @escaping (FightDataMove) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.gameName = gameName
        self.characterName = characterName
        self.editingMove = editingMove
        self.isCustom = isCustom
        self.gameCategories = gameCategories
        self.onSave = onSave
        self.onDelete = onDelete

        _moveName = State(initialValue: editingMove?.name ?? "")
        _moveCategory = State(initialValue: editingMove?.category ?? "_@special")
        _moveHitLevels = State(initialValue: editingMove?.hitLevels ?? "")
        _moveCondition = State(initialValue: editingMove?.condition ?? "")

        var preSteps: [EditorStep] = []
        if let move = editingMove {
            let parsed = InputParser.parse(move.input ?? "")
            for (seqIdx, sequence) in parsed.enumerated() {
                if seqIdx > 0 { preSteps.append(EditorStep(isBranch: true)) }
                for step in sequence {
                    var es = EditorStep()
                    es.direction = step.direction
                    es.buttons = step.buttons
                    es.isCharge = step.isCharge
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
        var isBranch: Bool = false

        var isEmpty: Bool { direction == nil && buttons.isEmpty && !isBranch }
    }

    struct EditorButton: Identifiable {
        let id = UUID()
        let key: String
        let label: String
        var isSelected: Bool = false
    }

    private static let defaultCapcomButtons: [EditorButton] = [
        EditorButton(key: "^E", label: "LP"),
        EditorButton(key: "^F", label: "MP"),
        EditorButton(key: "^G", label: "HP"),
        EditorButton(key: "^H", label: "LK"),
        EditorButton(key: "^I", label: "MK"),
        EditorButton(key: "^J", label: "HK"),
    ]

    static let fullButtonCatalog: [(key: String, label: String)] = [
        ("^E", "LP"), ("^F", "MP"), ("^G", "HP"),
        ("^H", "LK"), ("^I", "MK"), ("^J", "HK"),
        ("_A", "A"), ("_B", "B"), ("_C", "C"), ("_D", "D"),
        ("_P", "Punch"), ("_K", "Kick"),
        ("_G", "Guard"), ("_H", "Hover"), ("_S", "Start"),
        ("^S", "Start"), ("_O", "Charge"), ("_N", "Neutral"),
        ("_X", "X"), ("^W", "W"), ("^V", "V"), ("^U", "U"), ("^T", "T"), ("^M", "M"),
    ]

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
            Text(editorTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            moveInfoSection
            directionPadSection
            buttonPaletteSection
            modifierSection
            compressedPreviewRow

            stepListSection
                .frame(maxHeight: .infinity)

            Divider()
            actionButtons
        }
        .padding(AppSpacing.lg)
        .frame(minWidth: 550, minHeight: 600)
        .onAppear {
            loadSavedButtonPalette()
        }
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
        return MoveNotationTokenRow(tokens: tokens, compact: true)
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
                toks.append(.button(buttonTokenTypeFromKey(k)))
            }
            return toks
        }

        guard dirTokens.count == dirs.count else { return nil }
        return (dirTokens, btnTokens)
    }

    private func buttonTokenTypeFromKey(_ key: String) -> ButtonTokenType {
        if key == "^E" || key == "^F" || key == "^G" || key == "_P" {
            let strength: ButtonStrength = key == "^E" ? .low : key == "^F" ? .medium : .high
            return .punch(strength: strength)
        }
        if key == "^H" || key == "^I" || key == "^J" || key == "_K" {
            let strength: ButtonStrength = key == "^H" ? .low : key == "^I" ? .medium : .high
            return .kick(strength: strength)
        }
        if key == "_G" { return .grapple }
        return .generic(label: key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: ""))
    }

    // MARK: - Direction Pad

    private var directionPadSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(loc.localized("settings.moveList.editor.directions"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            let gridSize: CGFloat = 36
            let spacing: CGFloat = 4
            VStack(spacing: spacing) {
                ForEach([[7, 8, 9], [4, 5, 6], [1, 2, 3]] as [[Int]], id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(row, id: \.self) { dir in
                            Button(action: { addDirectionStep(dir) }) {
                                Image("NotationDir\(dir)")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(dir == 5 ? 10 : 6)
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
    }

    // MARK: - Button Palette

    private var buttonPaletteSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(loc.localized("settings.moveList.editor.buttons"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                Spacer()
                Button(action: { showButtonCatalog = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("Add")
                            .font(.caption)
                    }
                    .foregroundStyle(AppColors.brandAccent)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showButtonCatalog) {
                    buttonCatalogContent
                }
            }

            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(availableButtons) { btn in
                    Button(action: { addButtonStep(btn.key) }) {
                        VStack(spacing: 2) {
                            MoveNotationTokenView(
                                token: .button(editorButtonTokenType(for: btn)),
                                isHighlighted: true,
                                compact: true
                            )
                            Text(btn.label)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            availableButtons.removeAll { $0.id == btn.id }
                            saveButtonPalette()
                        } label: {
                            Label(loc.localized("settings.moveList.editor.removeFromPalette"), systemImage: "xmark.circle")
                        }
                    }
                }
            }
        }
    }

    private func editorButtonTokenType(for btn: EditorButton) -> ButtonTokenType {
        let key = btn.key
        if btn.label == "LP" || btn.label == "MP" || btn.label == "HP" || btn.label == "Punch" {
            let strength: ButtonStrength = {
                switch btn.label {
                case "LP": return .low
                case "MP": return .medium
                case "HP": return .high
                default: return .low
                }
            }()
            return .punch(strength: strength)
        }
        if btn.label == "LK" || btn.label == "MK" || btn.label == "HK" || btn.label == "Kick" {
            let strength: ButtonStrength = {
                switch btn.label {
                case "LK": return .low
                case "MK": return .medium
                case "HK": return .high
                default: return .low
                }
            }()
            return .kick(strength: strength)
        }
        if key == "_G" || btn.label == "Guard" { return .grapple }
        return .generic(label: btn.label)
    }

    private var buttonCatalogContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(loc.localized("settings.moveList.editor.buttonCatalog"))
                .font(.headline)
                .padding()

            let currentKeys = Set(availableButtons.map(\.key))
            ScrollView(.vertical) {
                FlowLayout(spacing: AppSpacing.sm) {
                    ForEach(Self.fullButtonCatalog, id: \.key) { catBtn in
                        let inPalette = currentKeys.contains(catBtn.key)
                        Button(action: {
                            if inPalette {
                                availableButtons.removeAll { $0.key == catBtn.key }
                            } else {
                                availableButtons.append(EditorButton(key: catBtn.key, label: catBtn.label))
                            }
                            saveButtonPalette()
                        }) {
                            VStack(spacing: 2) {
                                MoveNotationTokenView(
                                    token: .button(buttonTokenForCatalog(key: catBtn.key, label: catBtn.label)),
                                    isHighlighted: true,
                                    compact: true
                                )
                                Text(catBtn.label)
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(inPalette ? AppColors.brandAccent.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.xs)
                                    .stroke(inPalette ? AppColors.brandAccent : AppColors.cardBorder(colorScheme), lineWidth: inPalette ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .frame(width: 320, height: 360)
    }

    private func buttonTokenForCatalog(key: String, label: String) -> ButtonTokenType {
        editorButtonTokenType(for: EditorButton(key: key, label: label))
    }

    // MARK: - Modifiers

    private var modifierSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(loc.localized("settings.moveList.editor.modifiers"))
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
                Text(loc.localized("settings.moveList.editor.sequence"))
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
                                HStack {
                                    Text("|").font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                                    Spacer()
                                }
                                .padding(.leading, 4)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppSpacing.xs) {
                                    ForEach(branchIndices, id: \.self) { index in
                                        stepChip(step: steps[index], index: index)
                                    }
                                }
                                .padding(.horizontal, 2)
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

    private func stepChip(step: EditorStep, index: Int) -> some View {
        let isSelected = selectedStepIndex == index
        let tokens = buildStepTokens(step)

        return Button(action: { selectedStepIndex = isSelected ? nil : index }) {
            HStack(spacing: NotationMetrics.tokenSpacing) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    MoveNotationTokenView(token: token, isHighlighted: true, compact: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? AppColors.brandAccent.opacity(0.2) : AppColors.cardBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xs)
                    .stroke(isSelected ? AppColors.brandAccent : AppColors.cardBorder(colorScheme), lineWidth: isSelected ? 2 : 1)
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
    }

    private func buildStepTokens(_ step: EditorStep) -> [NotationToken] {
        if step.isBranch { return [.alternative] }
        var tokens: [NotationToken] = []
        if step.isNeutral {
            tokens.append(.direction(.neutral))
        } else if let dir = step.direction, let fdDir = fightDataDirection(from: dir) {
            tokens.append(step.isCharge ? .charge(fdDir) : .direction(fdDir))
        }
        for (i, key) in step.buttons.enumerated() {
            if i > 0 { tokens.append(.separator) }
            let btn = availableButtons.first(where: { $0.key == key })
            let label = btn?.label ?? key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: "")
            let mockBtn = EditorButton(key: key, label: label)
            tokens.append(.button(editorButtonTokenType(for: mockBtn)))
        }
        if step.isRapid { tokens.append(.rapidPress) }
        return tokens.isEmpty ? [.wait] : tokens
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
            Button(loc.localized("movelist.cancel")) { dismiss() }
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
        dismiss()
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
                var s = "_"
                if step.isCharge { s = "_O_" }
                s += "\(dir)"
                if !step.buttons.isEmpty {
                    let btns = step.buttons.map { $0.hasPrefix("^") ? $0 : "_\($0)" }.joined()
                    s += "_+" + btns
                }
                if step.isRapid { s += "_X" }
                current.append(s)
            } else if !step.buttons.isEmpty {
                let btns = step.buttons.map { $0.hasPrefix("^") ? $0 : "_\($0)" }.joined()
                var s = btns
                if step.isRapid { s += "_X" }
                current.append(s)
            } else if step.isRapid {
                current.append("_X")
            }
            branches[branches.count - 1] = current
        }
        return branches.map { $0.joined(separator: " ") }.joined(separator: " / ")
    }

    private func saveButtonPalette() {
        let keys = availableButtons.map(\.key)
        if let data = try? JSONEncoder().encode(keys),
           let str = String(data: data, encoding: .utf8) {
            AppSettings.set("moveListButtonPalette_\(gameName)", value: str)
        }
    }

    private func loadSavedButtonPalette() {
        if let saved = AppSettings.getString("moveListButtonPalette_\(gameName)"),
           let data = saved.data(using: .utf8),
           let keys = try? JSONDecoder().decode([String].self, from: data) {
            var buttons: [EditorButton] = []
            for key in keys {
                if let cat = Self.fullButtonCatalog.first(where: { $0.key == key }) {
                    buttons.append(EditorButton(key: cat.key, label: cat.label))
                } else {
                    buttons.append(EditorButton(key: key, label: key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: "")))
                }
            }
            availableButtons = buttons
        }
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
