import Foundation
import AppKit
import UserNotifications

@MainActor
public class NotificationService: ObservableObject {
    public static let shared = NotificationService()
    
    @Published var isAuthorized: Bool = false
    
    private init() {
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
        }
    }
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            self.isAuthorized = granted
            return granted
        } catch {
            print("Error requesting notification authorization: \(error)")
            return false
        }
    }
    
	func sendNotification(title: String, body: String) {
		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body
		content.sound = .default

		let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
		UNUserNotificationCenter.current().add(request)
	}

	func sendNotification(title: String, body: String, image: NSImage) {
		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body
		content.sound = .default

		if let attachment = Self.attachment(from: image) {
			content.attachments = [attachment]
		}

		let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
		UNUserNotificationCenter.current().add(request)
	}

	private static func attachment(from image: NSImage) -> UNNotificationAttachment? {
		guard let tiffData = image.tiffRepresentation,
			  let bitmap = NSBitmapImageRep(data: tiffData),
			  let pngData = bitmap.representation(using: .png, properties: [:]) else {
			return nil
		}

		let tempURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.appendingPathExtension("png")

		do {
			try pngData.write(to: tempURL)
			let attachment = try UNNotificationAttachment(
				identifier: "badge",
				url: tempURL,
				options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
			)
			return attachment
		} catch {
			return nil
		}
	}
}