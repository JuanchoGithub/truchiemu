import SwiftUI

// MARK: - Bezel

enum BezelStyle: String, Codable, CaseIterable {
    case none, tv, arcade, handheld

    var displayName: String {
        switch self {
        case .none:     return "None"
        case .tv:       return "TV Cabinet"
        case .arcade:   return "Arcade"
        case .handheld: return "Handheld"
        }
    }

    var gamePadding: EdgeInsets {
        switch self {
        case .none:     return EdgeInsets()
        case .tv:       return EdgeInsets(top: 60, leading: 80, bottom: 60, trailing: 80)
        case .arcade:   return EdgeInsets(top: 100, leading: 60, bottom: 120, trailing: 60)
        case .handheld: return EdgeInsets(top: 80, leading: 40, bottom: 80, trailing: 40)
        }
    }
}

struct BezelView: View {
    let style: BezelStyle

    var body: some View {
        ZStack {
            // Simple stylised bezels drawn in SwiftUI
            switch style {
            case .tv:       tvBezel
            case .arcade:   arcadeBezel
            case .handheld: handheldBezel
            case .none:     EmptyView()
            }
        }
    }

    private var tvBezel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40)
                .fill(LinearGradient(colors:[Color(white: 0.15), Color(white: 0.08)],
                                      startPoint: .top, endPoint: .bottom))
                .padding(8)
                .shadow(color: .black.opacity(0.8), radius: 24, x: 0, y: 12)
            // Screen cutout handled by padding
        }
        .ignoresSafeArea()
    }

    private var arcadeBezel: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors:[Color(hue: 0.65, saturation: 0.5, brightness: 0.2),
                                               Color(hue: 0.68, saturation: 0.6, brightness: 0.1)],
                                      startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
            // Marquee strip
            VStack {
                LinearGradient(colors:[Color(red: 0.1, green: 0.6, blue: 0.35), Color(red: 0.15, green: 0.65, blue: 0.55)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 80)
                    .overlay(
                        Text("TRUCHIE EMU")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(6)
                    )
                Spacer()
            }
        }
    }

    private var handheldBezel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.06)],
                                      startPoint: .top, endPoint: .bottom))
                .padding(4)
                .shadow(color: .black.opacity(0.9), radius: 30, x: 0, y: 16)
        }
        .ignoresSafeArea()
    }
}