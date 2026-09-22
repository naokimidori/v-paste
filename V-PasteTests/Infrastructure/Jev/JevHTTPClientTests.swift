import XCTest
@testable import V_Paste

final class JevHTTPClientTests: XCTestCase {
    private var session: URLSession!
    private var client: JevHTTPClient!
    private let testBaseURL = URL(string: "https://test.typesafe.ai")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        client = JevHTTPClient(baseURL: testBaseURL, session: session, timeoutInterval: 1.5)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        client = nil
        super.tearDown()
    }

    private func makeSampleRequest() -> JevDecisionRequest {
        let destination = DestinationContext(
            applicationName: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 1234,
            windowTitle: "Search",
            focusedRole: "AXTextField"
        )
        let candidate = JevCandidatePayload(
            key: "c0",
            type: "text",
            preview: "Sample Candidate Text",
            sourceApplication: "Notes",
            ageBucket: "recent",
            favorited: false
        )
        return JevDecisionRequest.makeRequest(destination: destination, candidates: [candidate])
    }

    func testDecideSuccessfulResponse() async throws {
        let sampleJSON = """
        {
          "model": "jev-latest",
          "answers": {
            "candidate": {
              "type": "choice",
              "choice": "c0",
              "confidence": 0.88,
              "probabilities": {
                "c0": 0.88,
                "none": 0.12
              }
            },
            "useful_match": {
              "type": "noul",
              "noul": 0.82
            }
          },
          "usage": {
            "input_tokens": 150,
            "output_tokens": 15
          }
        }
        """.data(using: .utf8)!

        var interceptedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            interceptedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, sampleJSON)
        }

        let request = makeSampleRequest()
        let response = try await client.decide(request, apiKey: "ts-test-key-12345")

        XCTAssertEqual(response.model, "jev-latest")
        XCTAssertEqual(response.answers.candidate.choice, "c0")
        XCTAssertEqual(response.answers.candidate.confidence, 0.88)
        XCTAssertEqual(response.answers.candidate.probabilities?["c0"], 0.88)
        XCTAssertEqual(response.answers.usefulMatch.noul, 0.82)
        XCTAssertEqual(response.usage?.inputTokens, 150)

        // 验证请求 Header
        XCTAssertEqual(interceptedRequest?.httpMethod, "POST")
        XCTAssertEqual(interceptedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer ts-test-key-12345")
        XCTAssertEqual(interceptedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(interceptedRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testDecideThrowsInvalidKeyOn401() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await client.decide(makeSampleRequest(), apiKey: "wrong-key")
            XCTFail("应抛出 invalidAPIKey")
        } catch let error as JevDecisionError {
            XCTAssertEqual(error, .invalidAPIKey)
        } catch {
            XCTFail("抛出了非预期错误: \(error)")
        }
    }

    func testDecideThrowsPermissionDeniedOn403() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await client.decide(makeSampleRequest(), apiKey: "no-perm-key")
            XCTFail("应抛出 permissionDenied")
        } catch let error as JevDecisionError {
            XCTAssertEqual(error, .permissionDenied)
        } catch {
            XCTFail("抛出了非预期错误: \(error)")
        }
    }

    func testDecideThrowsRateLimitedWithRetryAfterOn429() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "45"]
            )!
            return (response, Data())
        }

        do {
            _ = try await client.decide(makeSampleRequest(), apiKey: "valid-key")
            XCTFail("应抛出 rateLimited")
        } catch let error as JevDecisionError {
            XCTAssertEqual(error, .rateLimited(retryAfterSeconds: 45))
        } catch {
            XCTFail("抛出了非预期错误: \(error)")
        }
    }

    func testDecideThrowsServerErrorOn500() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 502,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await client.decide(makeSampleRequest(), apiKey: "valid-key")
            XCTFail("应抛出 serverError")
        } catch let error as JevDecisionError {
            XCTAssertEqual(error, .serverError(statusCode: 502))
        } catch {
            XCTFail("抛出了非预期错误: \(error)")
        }
    }

    func testDecideThrowsEmptyCandidatesWhenNoCandidates() async {
        let dest = DestinationContext(applicationName: "Safari", processIdentifier: 1)
        let emptyReq = JevDecisionRequest.makeRequest(destination: dest, candidates: [])

        do {
            _ = try await client.decide(emptyReq, apiKey: "valid-key")
            XCTFail("候选列表为空时不得发起网络请求")
        } catch let error as JevDecisionError {
            XCTAssertEqual(error, .emptyCandidates)
        } catch {
            XCTFail("抛出了非预期错误: \(error)")
        }
    }
}
