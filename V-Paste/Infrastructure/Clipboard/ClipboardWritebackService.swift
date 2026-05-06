import AppKit
import Foundation

enum ClipboardWritebackError: Error, Equatable {
    case missingPayload(ClipboardContentType)
    case missingImageAsset(String?)
    case writeFailed(ClipboardContentType)
}

final class ClipboardWritebackService {
    func write(
        item: ClipboardItem,
        to pasteboard: NSPasteboard = .general
    ) throws {
        let payload = try payload(for: item)
        pasteboard.clearContents()

        let didWrite: Bool
        switch payload {
        case .string(let text):
            didWrite = pasteboard.setString(text, forType: .string)
        case .url(let url):
            didWrite = pasteboard.writeObjects([url as NSURL])
        case .image(let image):
            didWrite = pasteboard.writeObjects([image])
        }

        guard didWrite else {
            throw ClipboardWritebackError.writeFailed(item.contentType)
        }
    }

    private func payload(for item: ClipboardItem) throws -> ClipboardWritebackPayload {
        switch item.contentType {
        case .text, .mixed:
            guard let plainText = item.plainText else {
                throw ClipboardWritebackError.missingPayload(item.contentType)
            }
            return .string(plainText)
        case .file:
            guard let filePath = item.filePath else {
                throw ClipboardWritebackError.missingPayload(.file)
            }
            return .url(URL(fileURLWithPath: filePath))
        case .image:
            if let filePath = item.filePath {
                return .url(URL(fileURLWithPath: filePath))
            }

            guard let assetPath = item.assetPath,
                  let image = NSImage(contentsOfFile: assetPath) else {
                throw ClipboardWritebackError.missingImageAsset(item.assetPath)
            }
            return .image(image)
        }
    }
}

private enum ClipboardWritebackPayload {
    case string(String)
    case url(URL)
    case image(NSImage)
}
