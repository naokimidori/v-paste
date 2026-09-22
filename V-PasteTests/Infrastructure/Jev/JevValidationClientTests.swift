import XCTest
@testable import V_Paste

/// 用于单元测试的 URLProtocol Mock
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("未设置 MockURLProtocol.requestHandler")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class JevValidationClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        super.tearDown()
    }

    func testValidateKeySuccessWithJevLatest() async throws {
        let modelsJSON = """
        {
            "models": [
                {"id": "gpt-4", "name": "GPT-4"},
                {"id": "jev-latest", "name": "Jev Latest"}
            ]
        }
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, modelsJSON)
        }

        let client = JevValidationClient(session: session)
        let result = await client.validateKey("valid-test-key")

        XCTAssertEqual(result, .valid)
        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer valid-test-key")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(capturedRequest?.url?.path, "/v1/models")
    }

    func testValidateKeySuccessWithOnlyNameFieldAndNoId() async throws {
        // 模拟实际生产环境 typesafe.ai 返回的数据格式（仅有 name 和 description，无 id）
        let modelsJSON = """
        {
            "models": [
                {"name": "jev-latest", "description": "TypeSafe latest model"},
                {"name": "jev-preview", "description": "TypeSafe preview model"}
            ]
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, modelsJSON)
        }

        let client = JevValidationClient(session: session)
        let result = await client.validateKey("valid-test-key")

        XCTAssertEqual(result, .valid)
    }

    func testValidateKeyModelUnavailableWhenMissingJev() async {
        let modelsJSON = """
        {
            "models": [
                {"id": "gpt-4", "name": "GPT-4"}
            ]
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, modelsJSON)
        }

        let client = JevValidationClient(session: session)
        let result = await client.validateKey("valid-key-no-model")

        XCTAssertEqual(result, .modelUnavailable)
    }

    func testValidateKeyReturnsInvalidKeyOn401() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = JevValidationClient(session: session)
        let result = await client.validateKey("unauthorized-key")

        XCTAssertEqual(result, .invalidKey)
    }

    func testValidateKeyReturnsPermissionDeniedOn403() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = JevValidationClient(session: session)
        let result = await client.validateKey("forbidden-key")

        XCTAssertEqual(result, .permissionDenied)
    }

    func testValidateKeyReturnsNetworkUnavailableOn429() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = JevValidationClient(session: session)
        let result = await client.validateKey("rate-limited-key")

        switch result {
        case .networkUnavailable:
            break
        default:
            XCTFail("应返回 networkUnavailable，实际为 \(result)")
        }
    }

    func testValidateKeyReturnsInvalidKeyForEmptyInput() async {
        let client = JevValidationClient(session: session)
        let result = await client.validateKey("   ")
        XCTAssertEqual(result, .invalidKey)
    }

    func testMockValidationClientReturnsConfiguredResult() async {
        let mock = MockJevValidationClient(resultToReturn: .permissionDenied)
        let result = await mock.validateKey("any-key")
        XCTAssertEqual(result, .permissionDenied)

        mock.resultToReturn = .valid
        let validResult = await mock.validateKey("any-key")
        XCTAssertEqual(validResult, .valid)
    }
}
