import Foundation
import Security

/// Jev 凭据存储错误类型
enum JevCredentialStoreError: Error, Equatable {
    /// Keychain 操作失败，附带系统状态码
    case keychainError(OSStatus)
    /// 字符串编码失败
    case stringEncodingError
}

/// Jev 凭据安全存储协议
protocol JevCredentialStoring: Sendable {
    /// 读取保存的 API Key
    func readApiKey() throws -> String?
    /// 保存或更新 API Key
    func saveApiKey(_ key: String) throws
    /// 删除已保存的 API Key
    func deleteApiKey() throws
    /// 检查是否存在有效的 API Key
    func hasApiKey() -> Bool
}

/// 基于 macOS Keychain 的 Jev 凭据安全存储实现
final class JevCredentialStore: JevCredentialStoring {
    /// 默认服务名称
    let serviceName: String
    /// 默认账户标识
    let accountName: String

    init(
        serviceName: String = "io.vpaste.app.jev",
        accountName: String = "apiKey"
    ) {
        self.serviceName = serviceName
        self.accountName = accountName
    }

    /// 从系统 Keychain 读取 API Key
    func readApiKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw JevCredentialStoreError.keychainError(status)
        }

        guard let data = item as? Data,
              let keyString = String(data: data, encoding: .utf8) else {
            throw JevCredentialStoreError.stringEncodingError
        }

        let trimmed = keyString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 将 API Key 安全保存或更新至系统 Keychain
    func saveApiKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmedKey.data(using: .utf8) else {
            throw JevCredentialStoreError.stringEncodingError
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw JevCredentialStoreError.keychainError(addStatus)
            }
            return
        }

        throw JevCredentialStoreError.keychainError(updateStatus)
    }

    /// 从 Keychain 中彻底移除 API Key
    func deleteApiKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw JevCredentialStoreError.keychainError(status)
        }
    }

    /// 快速检查是否存在 API Key，不抛出异常
    func hasApiKey() -> Bool {
        do {
            let key = try readApiKey()
            return key != nil && !key!.isEmpty
        } catch {
            return false
        }
    }
}

/// 用于单元测试与预览的内存版 Jev 凭据存储
final class MockJevCredentialStore: JevCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: String?

    init(initialKey: String? = nil) {
        self.storedKey = initialKey
    }

    func readApiKey() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedKey
    }

    func saveApiKey(_ key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        storedKey = trimmed.isEmpty ? nil : trimmed
    }

    func deleteApiKey() throws {
        lock.lock()
        defer { lock.unlock() }
        storedKey = nil
    }

    func hasApiKey() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedKey != nil && !storedKey!.isEmpty
    }
}
