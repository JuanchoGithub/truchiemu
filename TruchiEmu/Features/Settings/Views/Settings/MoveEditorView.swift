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
    let onSave: (FightDataMove) -> Void
    let onDelete: (() -> Void)?

    @State private var moveName: String = ""
    @State private var moveCategory: String = "_@special"
    @State private var steps: [EditorStep] = []
    @State private var selectedStepIndex: Int? = nil
    @State private var showCategoryPicker = false
    @State private var customCategoryText: String = ""
    @State private var isChargeMove = false
    @State private var chargeDirection: Int? = nil
    @State private var isAirMove = false
    @State private var isRapidPress = false
    @State private var holdButton = false

    @State private var availableButtons: [EditorButton] = MoveEditorView.defaultCapcomButtons
    @State private var showButtonCatalog = false

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

        var isEmpty: Bool { direction == nil && buttons.isEmpty }
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
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(editorTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            moveInfoSection
            directionPadSection
            buttonPaletteSection
            modifierSection
            stepListSection
            actionButtons
        }
        .padding(AppSpacing.lg)
        .frame(minWidth: 500, minHeight: 500)
        .onAppear {
            if let move = editingMove {
                moveName = move.name
                moveCategory = move.category
                loadMoveSteps(from: move)
                isChargeMove = move.isCharge
                chargeDirection = move.chargeDirectionValue
                isAirMove = move.isAir
                isRapidPress = move.isRapidPress
                holdButton = move.isHoldButton
            }
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
        if let standard = Self.standardCategories.first(where: { $0.key == moveCategory }) {
            return standard.label
        }
        if moveCategory.hasPrefix("_@") { return String(moveCategory.dropFirst(2)) }
        return moveCategory
    }

    private var categoryPickerContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(loc.localized("settings.moveList.editor.category"))
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, AppSpacing.sm)

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
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showButtonCatalog) {
                    buttonCatalogContent
                }
            }

            FlowLayout(spacing: AppSpacing.xs) {
                ForEach(availableButtons) { btn in
                    Button(action: { addButtonStep(btn.key) }) {
                        MoveNotationTokenView(
                            token: .button(editorButtonTokenType(for: btn)),
                            isHighlighted: true,
                            compact: true
                        )
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
            FlowLayout(spacing: AppSpacing.xs) {
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
                        HStack(spacing: 4) {
                            Image(systemName: inPalette ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(inPalette ? AppColors.brandAccent : AppColors.textTertiary(colorScheme))
                            Text(catBtn.label)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .frame(width: 280, height: 300)
    }

    // MARK: - Modifiers

    private var modifierSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(loc.localized("settings.moveList.editor.modifiers"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            HStack(spacing: AppSpacing.md) {
                Toggle(isOn: $isAirMove) {
                    Label("↑ Air", systemImage: "arrow.up")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $isChargeMove) {
                    Label("⏳ Charge", systemImage: "hourglass")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $isRapidPress) {
                    Label("⚡ Rapid", systemImage: "bolt")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }

            if isChargeMove {
                HStack(spacing: AppSpacing.xs) {
                    Text(loc.localized("settings.moveList.editor.chargeDir"))
                        .font(.system(size: 11))
                    ForEach([4, 6, 2, 8, 1, 3, 7, 9], id: \.self) { dir in
                        Button(action: { chargeDirection = dir }) {
                            Image("NotationDir\(dir)")
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(5)
                                .frame(width: 28, height: 28)
                                .foregroundStyle(chargeDirection == dir ? AppColors.brandAccent : .white)
                                .background(chargeDirection == dir ? AppColors.brandAccent.opacity(0.2) : AppColors.cardBackground(colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.xs)
                                        .stroke(chargeDirection == dir ? AppColors.brandAccent : AppColors.cardBorder(colorScheme), lineWidth: chargeDirection == dir ? 2 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            stepChip(step: step, index: index)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
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
        var directions: [[Int]] = []
        var buttons: [[String]] = []

        for step in steps {
            var dirStep: [Int] = []
            if let dir = step.direction { dirStep = [dir] }
            else if step.isNeutral { dirStep = [5] }
            directions.append(dirStep)
            buttons.append(step.buttons)
        }

        let rawInput = buildRawInput()
        let parsed = ParsedInput(
            raw: rawInput,
            directions: directions,
            buttons: buttons,
            charge: isChargeMove,
            chargeDirection: chargeDirection,
            air: isAirMove,
            rapidPress: isRapidPress,
            holdButton: holdButton,
            followUp: false,
            neutral: false,
            motion360: false
        )

        let move = FightDataMove(
            category: moveCategory,
            name: moveName,
            input: rawInput,
            parsedInput: parsed
        )

        onSave(move)
        dismiss()
    }

    private func buildRawInput() -> String {
        var parts: [String] = []
        if isAirMove { parts.append("_8") }
        if isChargeMove, let cd = chargeDirection { parts.append("_O_\(cd)") }
        for step in steps {
            if let dir = step.direction {
                var s = "_\(dir)"
                if step.isCharge { s = "_O" + s }
                if !step.buttons.isEmpty {
                    let btns = step.buttons.map { $0.hasPrefix("^") ? $0 : "_\($0)" }.joined()
                    s += btns
                }
                parts.append(s)
            } else if step.isNeutral {
                parts.append("_5")
            } else if !step.buttons.isEmpty {
                let btns = step.buttons.map { $0.hasPrefix("^") ? $0 : "_\($0)" }.joined()
                parts.append(btns)
            }
        }
        if isRapidPress { parts.append("_X") }
        return parts.joined(separator: " ")
    }

    private func loadMoveSteps(from move: FightDataMove) {
        guard let pi = move.parsedInput else { return }
        isAirMove = pi.air
        isChargeMove = pi.charge
        chargeDirection = pi.chargeDirection
        isRapidPress = pi.rapidPress
        holdButton = pi.holdButton

        let dirCount = pi.directions.count
        let btnCount = pi.buttons.count
        let maxCount = max(dirCount, btnCount)

        for i in 0..<maxCount {
            var step = EditorStep()
            if i < dirCount, let firstDir = pi.directions[i].first {
                step.direction = firstDir
                step.isCharge = pi.charge && pi.chargeDirection == firstDir
            }
            if i < btnCount {
                step.buttons = pi.buttons[i]
            }
            steps.append(step)
        }
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
