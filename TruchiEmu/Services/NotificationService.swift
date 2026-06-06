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

	func sendNotification(title: String, body: String, userInfo: [String: Any] = [:]) {
		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body
		content.sound = .default
		content.userInfo = userInfo

		let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
		UNUserNotificationCenter.current().add(request)
	}

	func sendNotification(title: String, body: String, image: NSImage, userInfo: [String: Any] = [:]) {
		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body
		content.sound = .default
		content.userInfo = userInfo

		if let attachment = Self.attachment(from: image) {
			content.attachments = [attachment]
		}

		let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
		UNUserNotificationCenter.current().add(request)
	}

	private static func attachment(from image: NSImage) -> UNNotificationAttachment? {
		let maxDimension: CGFloat = 256
		let sizedImage = resizeImage(image, maxDimension: maxDimension)

		guard let tiffData = sizedImage.tiffRepresentation,
			  let bitmap = NSBitmapImageRep(data: tiffData),
			  let pngData = bitmap.representation(using: .png, properties: [:]) else {
			return nil
		}

		let tempDir = FileManager.default.temporaryDirectory
		let badgeDir = tempDir.appendingPathComponent("TruchiEmuNotifications", isDirectory: true)
		try? FileManager.default.createDirectory(at: badgeDir, withIntermediateDirectories: true)

		let fileURL = badgeDir.appendingPathComponent(UUID().uuidString + ".png")

		do {
			try pngData.write(to: fileURL)
			let attachment = try UNNotificationAttachment(
				identifier: "badge",
				url: fileURL,
				options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
			)
			return attachment
		} catch {
			return nil
		}
	}

	private static func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
		let size = image.size
		guard size.width > maxDimension || size.height > maxDimension else { return image }

		let scale = min(maxDimension / size.width, maxDimension / size.height)
		let newSize = NSSize(width: size.width * scale, height: size.height * scale)

		let newImage = NSImage(size: newSize)
		newImage.lockFocus()
		image.draw(in: NSRect(origin: .zero, size: newSize),
				   from: NSRect(origin: .zero, size: size),
				   operation: .copy,
				   fraction: 1.0)
		newImage.unlockFocus()
		return newImage
	}
}
