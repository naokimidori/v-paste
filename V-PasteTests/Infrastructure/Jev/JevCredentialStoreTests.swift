import XCTest
@testable import V_Paste

final class JevCredentialStoreTests: XCTestCase {
    func testMockCredentialStoreLifecycle() throws {
        let store = MockJevCredentialStore()

        // 初始状态下无 Key
        XCTAssertNil(try store.readApiKey())
        XCTAssertFalse(store.hasApiKey())

        // 保存正常 Key
        try store.saveApiKey("test-api-key-12345")
        XCTAssertTrue(store.hasApiKey())
        let readKey = try store.readApiKey()
        XCTAssertEqual(readKey, "test-api-key-12345")

        // 覆盖更新 Key
        try store.saveApiKey("test-api-key-updated")
        let updatedKey = try store.readApiKey()
        XCTAssertEqual(updatedKey, "test-api-key-updated")

        // 保存空 Key 应重置为空
        try store.saveApiKey("   ")
        XCTAssertFalse(store.hasApiKey())
        XCTAssertNil(try store.readApiKey())

        // 再次保存后删除 Key
        try store.saveApiKey("another-key")
        XCTAssertTrue(store.hasApiKey())
        try store.deleteApiKey()
        XCTAssertNil(try store.readApiKey())
        XCTAssertFalse(store.hasApiKey())

        // 重复删除已删除的 Key 不应抛出异常
        XCTAssertNoThrow(try store.deleteApiKey())
    }

    func testCredentialStoreDefaultConfiguration() {
        let store = JevCredentialStore()
        XCTAssertEqual(store.serviceName, "io.vpaste.app.jev")
        XCTAssertEqual(store.accountName, "apiKey")
    }
}
