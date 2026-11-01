import Foundation

protocol CookieStoring {
    func save(_ cookieHeader: String) throws
    func load() throws -> String?
    func clear() throws
    func hasCookie() throws -> Bool
}

struct KeychainCookieStore: CookieStoring {
    var accessGroup: String?

    init(accessGroup: String? = SharedStorage.resolvedKeychainAccessGroup()) {
        self.accessGroup = accessGroup
    }

    func save(_ cookieHeader: String) throws {
        let normalized = CookieHeader.normalize(cookieHeader)
        guard !normalized.isEmpty else { throw UsageFetchError.missingCookie }
        let data = Data(normalized.utf8)
        let query = baseQuery()
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrSynchronizable as String] = kCFBooleanFalse
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }

    func load() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.status(errSecDecode)
        }
        return string
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    func hasCookie() throws -> Bool {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw KeychainError.status(status)
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SharedStorage.keychainService,
            kSecAttrAccount as String: SharedStorage.keychainAccount,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

enum KeychainError: Error, Equatable, LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        let code = osStatus
        switch code {
        case errSecItemNotFound:
            return "No cookie is stored in the Keychain."
        case errSecMissingEntitlement:
            return "Keychain sharing isn't available in this build. Set DEVELOPMENT_TEAM and sign the app."
        case errSecInteractionNotAllowed:
            return "The Keychain is locked. Unlock this Mac and try again."
        default:
            if let message = SecCopyErrorMessageString(code, nil) as String? {
                return "Keychain error: \(message)"
            }
            return "Keychain error (\(code))."
        }
    }

    private var osStatus: OSStatus {
        switch self {
        case .status(let code):
            return code
        }
    }
}
