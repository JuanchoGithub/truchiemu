import SwiftUI

struct MoveListOverlay: View {
    @ObservedObject var viewModel: MoveListOverlayViewModel
    @ObservedObject var windowController: StandaloneGameWindowController
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0)
                .ignoresSafeArea()

            if viewModel.needsCharacterSelection {
                characterSelectionPanel
            } else if viewModel.isOverlayVisible {
                moveListPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(viewModel.isOverlayVisible || viewModel.needsCharacterSelection)
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
                }
                .frame(width: 220)

                Divider()

                notationLegendSidebar
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
        .frame(width: 520, height: min(CGFloat(viewModel.characters.count) * 36 + 100, 300))
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 10)
        .padding(.bottom, windowController.toolbarBottomInset)
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
                    token: .button(MoveNotationRenderer.resolveButtonType(key, gameData: viewModel.moveListService.currentGameData)),
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
        .padding(.bottom, windowController.toolbarBottomInset)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isOverlayVisible)
    }

    private var headerSection: some View {
        HStack(spacing: 6) {
            Button(action: {
                windowController.toggleMoveListOverlay()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var moveListSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(viewModel.filteredMoves.enumerated()), id: \.offset) { _, move in
                MoveEntryRow(
                    move: move,
                    isMatched: viewModel.matchedMoveName == move.name
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
        for (i, key) in sorted.enumerated() {
            if i > 0 { tokens.append(.separator) }
            tokens.append(.button(MoveNotationRenderer.resolveButtonType(key, gameData: viewModel.moveListService.currentGameData)))
        }
        return tokens
    }
}

struct MoveEntryRow: View {
    let move: ResolvedMove
    let isMatched: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            MoveNotationTokenRow(
                tokens: move.tokens,
                matchedStepCount: move.matchedStepCount,
                compact: false
            )

        VStack(alignment: .leading, spacing: 1) {
            if !move.name.isEmpty {
                Text(move.name)
                    .font(.system(size: 9, weight: .semibold))
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
