import SwiftUI
import AppKit

struct SystemControlsMappingView: View {
    @EnvironmentObject var controllerService: ControllerService
    let systemID: String
    let systemName: String
    @Environment(\.dismiss) var dismiss

    @State private var mapping: KeyboardMapping = KeyboardMapping(buttons: [:])
    @State private var listeningFor: RetroButton? = nil

    private var relevantButtons: [RetroButton] {
        switch systemID {
        case "nes":      return [.up, .down, .left, .right, .a, .b, .start, .select]
        case "snes":     return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .start, .select]
        case "genesis":  return [.up, .down, .left, .right, .a, .b, .c, .x, .y, .z, .start, .select]
        case "mame", "fba", "arcade": return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .coin1, .start1]
        default:         return RetroButton.allCases
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(relevantButtons, id: \.self) { button in
                        HStack {
                            Text(button.displayName)
                                .font(.body)
                            Spacer()
                            Button {
                                listeningFor = (listeningFor == button) ? nil : button
                            } label: {
                                Text(keyLabel(for: button))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(listeningFor == button ? Color.purple : Color.secondary.opacity(0.1))
                                    .cornerRadius(6)
                                    .foregroundColor(listeningFor == button ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding()
            }
            
            footer
        }
        .frame(width: 320, height: 500)
        .onAppear { mapping = controllerService.keyboardMapping(for: systemID) }
        .background(KeyEventView(listeningFor: $listeningFor) { code in
            if let button = listeningFor {
                mapping.buttons[button] = code
                controllerService.updateKeyboardMapping(mapping, for: systemID)
                listeningFor = nil
            }
        })
    }

    private var header: some View {
        HStack {
            Text("\(systemName) Controls")
                .font(.headline)
            Spacer()
            Button("Reset to Defaults") {
                mapping = KeyboardMapping.defaults(for: systemID)
                controllerService.updateKeyboardMapping(mapping, for: systemID)
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
        }
        .padding()
    }

    private func keyLabel(for button: RetroButton) -> String {
        if listeningFor == button { return "Press Key…" }
        guard let code = mapping.buttons[button] else { return "—" }
        let names: [UInt16: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
            11:"B",12:"Q",13:"W",14:"E",15:"R",17:"T",16:"Y",32:"U",34:"I",
            31:"O",35:"P",36:"Enter",53:"Esc",123:"Left",124:"Right",
            125:"Down",126:"Up",49:"Space",48:"Tab"
        ]
        return names[code] ?? "Key \(code)"
    }
}

struct KeyEventView: NSViewRepresentable {
    @Binding var listeningFor: RetroButton?
    let onKeyEvent: (UInt16) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyEvent: onKeyEvent, listeningFor: $listeningFor)
    }

    class Coordinator: NSObject {
        let onKeyEvent: (UInt16) -> Void
        @Binding var listeningFor: RetroButton?
        var monitor: Any?

        init(onKeyEvent: @escaping (UInt16) -> Void, listeningFor: Binding<RetroButton?>) {
            self.onKeyEvent = onKeyEvent
            self._listeningFor = listeningFor
            super.init()
            self.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                if self?.listeningFor != nil {
                    self?.onKeyEvent(event.keyCode)
                    return nil // Swallowed
                }
                return event
            }
        }
        
        deinit {
            if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
