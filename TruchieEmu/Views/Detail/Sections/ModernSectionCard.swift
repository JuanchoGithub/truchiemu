import SwiftUI

// MARK: - Modern Section Card Component (Non-collapsible)

struct ModernSectionCard<Content: View>: View {
    let title: String?
    let icon: String?
    var badge: String? = nil
    var showHeader: Bool = true
    @ViewBuilder let content: Content
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        title: String? = nil,
        icon: String? = nil,
        badge: String? = nil,
        showHeader: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.showHeader = showHeader
        self.content = content()
    }
    
    private var sectionTitleColor: Color {
        colorScheme == .dark ? .white.opacity(0.6) : .primary.opacity(0.6)
    }
    
    private var sectionIconColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .secondary
    }
    
    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.secondary.opacity(0.2)
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : .secondary.opacity(0.05)
    }
    
    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : .secondary.opacity(0.15)
    }
    
    // Accent badge color — adapts for light mode readability
    private var badgeBackground: Color {
        colorScheme == .dark ? Color.blue.opacity(0.3) : .blue.opacity(0.15)
    }
    private var badgeForeground: Color {
        colorScheme == .dark ? .white : .blue
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader, let title = title {
                HStack(spacing: 10) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundColor(sectionIconColor)
                            .font(.body)
                    }
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(sectionTitleColor)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    if let badge = badge {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badgeBackground)
                            .foregroundColor(badgeForeground)
                            .cornerRadius(6)
                    }
                    Spacer()
                }
                
                Divider()
                    .padding(.vertical, 10)
                    .overlay(dividerColor)
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }
}