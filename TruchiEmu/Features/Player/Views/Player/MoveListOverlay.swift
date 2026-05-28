import SwiftUI

struct MoveListOverlay: View {
    @ObservedObject var viewModel: MoveListOverlayViewModel
    @ObservedObject var windowController: StandaloneGameWindowController
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        ZStack {
            Color.black.opacity(viewModel.needsCharacterSelection ? 0.5 : 0)
                .ignoresSafeArea()

            if viewModel.needsCharacterSelection {
                characterSelectionView
            } else if viewModel.isOverlayVisible {
                moveListContentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(viewModel.isOverlayVisible || viewModel.needsCharacterSelection)
    }

    private var characterSelectionView: some View {
        VStack(spacing: 0) {
            Spacer()

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
                                Button(action: {
                                    viewModel.selectPendingCharacter(character)
                                }) {
                                    HStack {
                                        Text(character.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(viewModel.pendingCharacter?.id == character.id ? AppColors.brandAccent : .white)

                                        Spacer()

                                        if viewModel.pendingCharacter?.id == character.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(AppColors.brandAccent)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if character.id != viewModel.characters.last?.id {
                                    Divider().opacity(0.3)
                                }
                            }
                        }
                    }

                    Divider()

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

                        Button(action: {
                            windowController.confirmPendingCharacter()
                        }) {
                            Text(loc.localized("movelist.ok"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(viewModel.pendingCharacter != nil ? .white : .white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(viewModel.pendingCharacter != nil ? AppColors.brandAccent : AppColors.brandAccent.opacity(0.3))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.pendingCharacter == nil)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .frame(width: 260, height: min(CGFloat(viewModel.characters.count) * 44 + 150, 440))

                notationLegendSidebar
                    .frame(width: 200, height: min(CGFloat(viewModel.characters.count) * 44 + 150, 440))
            }
            .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 10)
            .padding(.bottom, windowController.toolbarBottomInset)
        }
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
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.localized("movelist.notationLegend"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 16)

                if !buttonEntries.isEmpty {
                    Text(loc.localized("movelist.buttons"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))

                    ForEach(buttonEntries, id: \.key) { key, a in
                        HStack {
                            Text(a)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(AppColors.brandAccent)
                                .frame(width: 24, alignment: .leading)
                            Text(labels[key] ?? "")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                }

                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.localized("movelist.symbols"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))

                    HStack(spacing: 2) {
                        Text(verbatim: "↑").font(.system(size: 11)).foregroundColor(.cyan.opacity(0.7))
                        Text(verbatim: "= Air").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                    }
                    HStack(spacing: 2) {
                        Text(verbatim: "⏳").font(.system(size: 11)).foregroundColor(.yellow.opacity(0.7))
                        Text(verbatim: "= Hold/Charge").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                    }
                    HStack(spacing: 2) {
                        Text(verbatim: "●").font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                        Text(verbatim: "= Neutral").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                    }
                HStack(spacing: 2) {
                    Text(verbatim: "⚡").font(.system(size: 11)).foregroundColor(.yellow.opacity(0.7))
                    Text(verbatim: "= Rapid press").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                }
                }

                if !catEntries.isEmpty {
                    Divider().opacity(0.3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("movelist.categories"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))

                        ForEach(catEntries, id: \.key) { key, label in
                            HStack {
                                Text(key.replacingOccurrences(of: "_", with: ""))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.3))
                                    .frame(width: 18, alignment: .leading)
                                Text(label)
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
        }
    }

    private var moveListContentView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                moveListSection
                inputSequenceSection
                notesSection
            }
            .padding(.leading, 16)
            .padding(.top, 12)
            Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isOverlayVisible)
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            Button(action: {
                windowController.toggleMoveListOverlay()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            if let charName = viewModel.selectedCharacterName {
                Text(charName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var moveListSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.filteredMoves.isEmpty && viewModel.hasGameData {
                noMatchView
            } else {
                ForEach(viewModel.filteredMoves) { move in
                    MoveEntryRow(
                        move: move,
                        isMatched: viewModel.matchedMoveName == move.name,
                        controlLabels: viewModel.moveListService.controlLabels
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var noMatchView: some View {
        Text(loc.localized("movelist.noMatch"))
            .font(.caption2)
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.4))
            )
    }

    private var inputSequenceSection: some View {
        Group {
            if !viewModel.inputDirections.isEmpty || !viewModel.inputButtons.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.inputDirections.enumerated()), id: \.offset) { index, dir in
                    HStack(spacing: 1) {
                        if viewModel.inputDirectionCharges.count > index && viewModel.inputDirectionCharges[index] {
                            Text(verbatim: "⏳")
                                .font(.system(size: 11))
                                .foregroundColor(.yellow.opacity(0.7))
                        }
                        Text(dir.symbol)
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.brandAccent)
                    }
                }
                    ForEach(Array(viewModel.inputButtons.enumerated()), id: \.offset) { _, btns in
                        Text(resolveButtonSet(btns))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.brandAccent)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.brandAccent.opacity(0.4), lineWidth: 1)
                        )
                )
            }
        }
    }

    private var notesSection: some View {
        Group {
            if viewModel.inputDirections.isEmpty && viewModel.inputButtons.isEmpty {
                if !viewModel.commonNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.commonNotes, id: \.self) { note in
                            Text(note)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.35))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
                if !viewModel.cheatNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("movelist.cheatNotes"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                        ForEach(viewModel.cheatNotes, id: \.self) { note in
                            Text(note)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
            }
        }
    }

    private func resolveButtonSet(_ buttons: Set<String>) -> String {
        buttons.map { viewModel.moveListService.resolveButtonLabel($0) }
            .sorted()
            .joined(separator: "+")
    }
}

struct MoveEntryRow: View {
    let move: ResolvedMove
    let isMatched: Bool
    let controlLabels: [String: String]
    @Environment(\.colorScheme) private var colorScheme

    private var tokens: [NotationToken] {
        tokenizeNotation(move.notation)
    }

    var body: some View {
        HStack(spacing: 0) {
            notationView

            VStack(alignment: .leading, spacing: 1) {
                Text(move.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isMatched ? AppColors.brandAccent : .white)
                HStack(spacing: 2) {
                    if move.isAir {
                        Text(verbatim: "AIR")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    if move.isCharge {
                        Text(verbatim: "CHARGE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.yellow.opacity(0.6))
                    }
                    if move.isMotion360 {
                        Text(verbatim: "360")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.orange.opacity(0.6))
                    }
                    Text(move.categoryLabel)
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .padding(.leading, 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isMatched ? AppColors.brandAccent.opacity(0.15) : Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isMatched ? AppColors.brandAccent.opacity(0.6) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
        .overlay(alignment: .leading) {
            if isMatched {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.brandAccent)
                    .frame(width: 3, height: 20)
                    .offset(x: -1)
            }
        }
    }

    private var notationView: some View {
        let stepToTokenIndex = buildStepToTokenMap()
        return HStack(spacing: 2) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                let stepIdx = stepToTokenIndex[index]
                let isHighlighted = stepIdx != nil && stepIdx! < move.matchedStepCount
                Group {
                    switch token {
                    case .direction(let symbol):
                        Text(symbol)
                            .font(.system(size: 14, weight: .medium))
                    case .button(let label):
                        Text(label)
                            .font(.system(size: 12, weight: .bold))
                    case .separator:
                        Text(verbatim: "+")
                            .font(.system(size: 11, weight: .medium))
                    case .air:
                        Text(verbatim: "↑")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.cyan.opacity(0.7))
                    case .charge:
                        Text(verbatim: "⏳")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow.opacity(0.7))
                    case .holdButton:
                        Text(verbatim: "⏳")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow.opacity(0.7))
        case .neutral:
            Text(verbatim: "●")
                .font(.system(size: 14, weight: .medium))
                    case .rapidPress:
                        Text(verbatim: "⚡")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow.opacity(0.7))
                    }
                }
                .foregroundColor(isHighlighted ? AppColors.brandAccent : defaultColor(for: token))
            }
        }
    }

    private func buildStepToTokenMap() -> [Int: Int] {
        var map: [Int: Int] = [:]
        var stepIdx = 0
        for (tokenIdx, token) in tokens.enumerated() {
            switch token {
            case .direction, .button:
                map[tokenIdx] = stepIdx
                stepIdx += 1
            case .separator, .air, .charge, .holdButton, .neutral, .rapidPress:
                break
            }
        }
        return map
    }

    private func tokenizeNotation(_ notation: String) -> [NotationToken] {
        var tokens: [NotationToken] = []
        let directionSymbols: Set<Character> = ["↙", "↓", "↘", "←", "●", "→", "↖", "↑", "↗"]
        var i = notation.startIndex

        while i < notation.endIndex {
            let char = notation[i]

            if char == " " {
                i = notation.index(after: i)
                continue
            }

            if char == "⏳" {
                i = notation.index(after: i)
                if i < notation.endIndex && directionSymbols.contains(notation[i]) {
                    tokens.append(.charge)
                    continue
                }
                tokens.append(.holdButton)
                continue
            }

            if char == "+" {
                if let last = tokens.last, case .separator = last {} else {
                    tokens.append(.separator)
                }
                i = notation.index(after: i)
                continue
            }

        if char == "⚡" {
            tokens.append(.rapidPress)
            i = notation.index(after: i)
            continue
        }

            if char == "↑" && tokens.last != .charge && !tokens.contains(where: { if case .direction = $0 { return true } else { return false } }) {
                tokens.append(.air)
                i = notation.index(after: i)
                continue
            }

            if directionSymbols.contains(char) && char != "●" {
                tokens.append(.direction(String(char)))
                i = notation.index(after: i)
                continue
            }

            if char == "●" {
                tokens.append(.neutral)
                i = notation.index(after: i)
                continue
            }

            var buttonBuf = ""
            while i < notation.endIndex {
                let c = notation[i]
                if c == " " || c == "+" || c == "⏳" || directionSymbols.contains(c) || c == "⚡" { break }
                buttonBuf.append(c)
                i = notation.index(after: i)
            }
            if !buttonBuf.isEmpty {
                tokens.append(.button(buttonBuf))
            }
        }

        return tokens
    }

    private func defaultColor(for token: NotationToken) -> Color {
        switch token {
        case .direction, .button: return .white.opacity(0.4)
        case .separator: return .white.opacity(0.25)
        case .air: return .cyan.opacity(0.7)
        case .charge, .holdButton: return .yellow.opacity(0.7)
        case .neutral: return .white.opacity(0.3)
        case .rapidPress: return .yellow.opacity(0.7)
        }
    }
}

enum NotationToken: Equatable {
    case direction(String)
    case button(String)
    case separator
    case air
    case charge
    case holdButton
    case neutral
    case rapidPress
}
