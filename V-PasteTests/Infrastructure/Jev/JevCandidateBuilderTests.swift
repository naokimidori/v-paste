import XCTest
@testable import V_Paste

final class JevCandidateBuilderTests: XCTestCase {
    private var builder: JevCandidateBuilder!
    private let fixedDate = Date(timeIntervalSince1970: 10_000_000)

    override func setUp() {
        super.setUp()
        builder = JevCandidateBuilder(dateProvider: { self.fixedDate })
    }

    private func makeItem(
        id: UUID = UUID(),
        type: ClipboardContentType = .text,
        title: String = "Test Title",
        text: String? = "Test plain text",
        fileName: String? = nil,
        filePath: String? = nil,
        isFavorited: Bool = false,
        sourceBundleID: String? = nil,
        copiedAt: Date? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            contentType: type,
            sourceHash: "hash-\(id.uuidString)",
            displayTitle: title,
            plainText: text,
            urlString: nil,
            fileName: fileName,
            filePath: filePath,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: copiedAt ?? fixedDate,
            lastCopiedAt: copiedAt ?? fixedDate,
            contentSize: 100,
            utiTypes: ["public.utf8-plain-text"],
            isFavorited: isFavorited,
            sourceAppName: "TestApp",
            sourceAppBundleIdentifier: sourceBundleID
        )
    }

    func testBlocksCandidatesWhenDestinationIsSecureField() {
        let secureDestination = DestinationContext(
            applicationName: "1Password",
            processIdentifier: 111,
            isSecureField: true
        )
        let items = [makeItem(), makeItem()]

        let prepared = builder.prepareCandidates(
            from: items,
            destination: secureDestination,
            ignoredBundleIdentifiers: [],
            userApiKey: nil
        )

        XCTAssertTrue(prepared.candidates.isEmpty, "安全密码框不得产生任何候选")
        XCTAssertTrue(prepared.keyToItemIDMap.isEmpty)
    }

    func testBlocksCandidatesWhenDestinationIsInIgnoredList() {
        let destination = DestinationContext(
            applicationName: "SecretApp",
            bundleIdentifier: "com.secret.vault",
            processIdentifier: 222
        )
        let items = [makeItem()]

        let prepared = builder.prepareCandidates(
            from: items,
            destination: destination,
            ignoredBundleIdentifiers: ["com.secret.vault"],
            userApiKey: nil
        )

        XCTAssertTrue(prepared.candidates.isEmpty, "目标应用在忽略列表中时不应产生候选")
    }

    func testMaxCandidateCountCappedAt40() {
        let destination = DestinationContext(
            applicationName: "TextEdit",
            processIdentifier: 333
        )
        // 创建 50 个普通候选
        var items: [ClipboardItem] = []
        for i in 0..<50 {
            items.append(makeItem(title: "Item \(i)", text: "Content \(i)"))
        }

        let prepared = builder.prepareCandidates(
            from: items,
            destination: destination,
            ignoredBundleIdentifiers: [],
            userApiKey: nil
        )

        XCTAssertEqual(prepared.candidates.count, 40, "无论历史有多少项，发往云端的候选硬上限为 40")
        XCTAssertEqual(prepared.keyToItemIDMap.count, 40)
        XCTAssertEqual(prepared.candidates.first?.key, "c0")
        XCTAssertEqual(prepared.candidates.last?.key, "c39")
    }

    func testDropsCandidateContainingHardcodedSecret() {
        let destination = DestinationContext(
            applicationName: "Notes",
            processIdentifier: 444
        )
        let safeItem = makeItem(title: "会议记录", text: "明天下午两点讨论季度目标")
        let secretItem = makeItem(title: "API密钥", text: "sk-proj-1234567890abcdef1234567890")

        let prepared = builder.prepareCandidates(
            from: [safeItem, secretItem],
            destination: destination,
            ignoredBundleIdentifiers: [],
            userApiKey: nil
        )

        XCTAssertEqual(prepared.candidates.count, 1, "包含机密 Key 的条目必须被整条拦截")
        XCTAssertEqual(prepared.candidates.first?.preview, "明天下午两点讨论季度目标")
        XCTAssertEqual(prepared.keyToItemIDMap["c0"], safeItem.id)
    }

    func testFilePathAndImageBinaryIsolation() {
        let destination = DestinationContext(
            applicationName: "Finder",
            processIdentifier: 555
        )
        let fileItem = makeItem(
            type: .file,
            title: "PrivateDocument.pdf",
            fileName: "PrivateDocument.pdf",
            filePath: "/Users/secret/Documents/PrivateDocument.pdf"
        )
        let imageItem = makeItem(
            type: .image,
            title: "Screenshot 2026.png",
            text: nil
        )

        let prepared = builder.prepareCandidates(
            from: [fileItem, imageItem],
            destination: destination,
            ignoredBundleIdentifiers: [],
            userApiKey: nil
        )

        for candidate in prepared.candidates {
            XCTAssertFalse(candidate.preview.contains("/Users/"), "候选预览严禁泄漏本地绝对路径")
        }
    }

    func testTokenOverlapBoostsRanking() {
        let destination = DestinationContext(
            applicationName: "Chrome",
            processIdentifier: 666,
            windowTitle: "Search for Swift Concurrency Tutorial"
        )
        let unrelatedItem = makeItem(
            title: "Shopping List",
            text: "Apples, Bananas, Milk",
            copiedAt: fixedDate
        )
        let matchedItem = makeItem(
            title: "Programming Notes",
            text: "Swift concurrency tutorial and async await guidelines",
            copiedAt: fixedDate - 3600 // 复制时间比 shopping list 早1小时
        )

        let prepared = builder.prepareCandidates(
            from: [unrelatedItem, matchedItem],
            destination: destination,
            ignoredBundleIdentifiers: [],
            userApiKey: nil
        )

        XCTAssertEqual(prepared.candidates.first?.key, "c0")
        XCTAssertEqual(prepared.keyToItemIDMap["c0"], matchedItem.id, "高词项命中的候选排在更优先的位置")
    }

    // MARK: - JEV-005: 真实文件与链接分类测试

    func testRealFileWithFileURLNotClassifiedAsLink() {
        let destination = DestinationContext(
            applicationName: "Slack",
            processIdentifier: 777
        )
        // 模拟 ClipboardNormalizer 为文件生成的真实数据形态：带有 file:// 的 urlString
        let fileItem = ClipboardItem(
            id: UUID(),
            contentType: .file,
            sourceHash: "file:///Users/john/Documents/quarterly-report.pdf",
            displayTitle: "quarterly-report.pdf",
            plainText: nil,
            urlString: "file:///Users/john/Documents/quarterly-report.pdf",
            fileName: "quarterly-report.pdf",
            filePath: "/Users/john/Documents/quarterly-report.pdf",
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: fixedDate,
            lastCopiedAt: fixedDate,
            contentSize: 1024,
            utiTypes: ["com.adobe.pdf"],
            isFavorited: false,
            sourceAppName: "Finder",
            sourceAppBundleIdentifier: "com.apple.finder"
        )

        let prepared = builder.prepareCandidates(
            from: [fileItem],
            destination: destination,
            ignoredBundleIdentifiers: [],
            userApiKey: nil
        )

        XCTAssertEqual(prepared.candidates.count, 1)
        let candidate = prepared.candidates.first!
        XCTAssertEqual(candidate.type, "file", "带有 file:// URL 的真实文件必须归类为 file，绝不得被误标为 link")
        XCTAssertEqual(candidate.preview, "quarterly-report.pdf")
        XCTAssertFalse(candidate.preview.contains("/Users/"), "绝不上报本地绝对路径")
    }

    func testRealImageWithFileURLNotClassifiedAsLink() {
        let destination = DestinationContext(
            applicationName: "Feishu",
            processIdentifier: 888
        )
        let imageItem = ClipboardItem(
            id: UUID(),
            contentType: .image,
            sourceHash: "file:///Users/john/Pictures/design-spec.png",
            displayTitle: "design-spec.png",
            plainText: nil,
            urlString: "file:///Users/john/Pictures/design-spec.png",
            fileName: "design-spec.png",
            filePath: "/Users/john/Pictures/design-spec.png",
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: fixedDate,
            lastCopiedAt: fixedDate,
            contentSize: 2048,
            utiTypes: ["public.png"],
            isFavorited: false,
            sourceAppName: "Finder",
            sourceAppBundleIdentifier: "com.apple.finder"
        )

        let prepared = builder.prepareCandidates(
            from: [imageItem],
            destination: destination,
            ignoredBundleIdentifiers: [],
            userApiKey: nil
        )

        XCTAssertEqual(prepared.candidates.count, 1)
        let candidate = prepared.candidates.first!
        XCTAssertEqual(candidate.type, "image", "带有 file:// URL 的真实图片必须归类为 image，绝不得误标为 link")
    }

    func testWebURLIsCorrectlyClassifiedAsLink() {
        let destination = DestinationContext(
            applicationName: "Safari",
            processIdentifier: 999
        )
        let webItem = ClipboardItem(
            id: UUID(),
            contentType: .text,
            sourceHash: "https://typesafe.ai/docs",
            displayTitle: "https://typesafe.ai/docs",
            plainText: "https://typesafe.ai/docs",
            urlString: "https://typesafe.ai/docs",
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: fixedDate,
            lastCopiedAt: fixedDate,
            contentSize: 24,
            utiTypes: ["public.utf8-plain-text"],
            isFavorited: false,
            sourceAppName: "Safari",
            sourceAppBundleIdentifier: "com.apple.Safari"
        )

        let prepared = builder.prepareCandidates(
            from: [webItem],
            destination: destination,
            ignoredBundleIdentifiers: [],
            userApiKey: nil
        )

        XCTAssertEqual(prepared.candidates.count, 1)
        let candidate = prepared.candidates.first!
        XCTAssertEqual(candidate.type, "link", "HTTP/HTTPS 链接必须归类为 link")
    }
}
