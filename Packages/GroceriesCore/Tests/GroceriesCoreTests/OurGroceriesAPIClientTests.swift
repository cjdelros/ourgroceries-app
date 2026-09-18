import XCTest
@testable import GroceriesCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class OurGroceriesAPIClientTests: XCTestCase {
    func testLoginBootstrapsAndPostsFixedOriginCommands() async throws {
        let transport = FixtureTransport(replies: [
            .html("<script> var g_teamId = \"team-1\"; const g_staticMetalist = 'meta'; </script>"),
            .html("<script>var g_teamId='team-1'</script>"),
            .json("{\"lists\":[{\"listId\":\"list-1\",\"name\":\"Groceries\"}]}")
        ])
        let client = OurGroceriesAPIClient(transport: transport)
        try await client.signIn(email: "person@example.test", password: "secret")
        let lists = try await client.overview()
        XCTAssertEqual(lists, [ShoppingList(id: "list-1", name: "Groceries")])
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://www.ourgroceries.com/sign-in",
            "https://www.ourgroceries.com/your-lists/",
            "https://www.ourgroceries.com/your-lists/"
        ])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
        let payload = try XCTUnwrap(requests[2].httpBody).jsonObject() as! [String: Any]
        XCTAssertEqual(payload["command"] as? String, "getOverview")
        XCTAssertEqual(payload["teamId"] as? String, "team-1")
    }

    func testMalformedBootstrapFailsWithoutSendingCommand() async throws {
        let transport = FixtureTransport(replies: [.html("signed in"), .html("<html>no team</html>")])
        let client = OurGroceriesAPIClient(transport: transport)
        do { try await client.signIn(email: "a", password: "b"); XCTFail("expected failure") }
        catch let error as OurGroceriesAPIError { XCTAssertEqual(error, .incompatibleResponse("bootstrap missing g_teamId")) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testInsertRequiresPositiveAcknowledgement() async throws {
        let transport = FixtureTransport(replies: [
            .html("ok"), .html("<script>g_teamId = \"team\"</script>"), .json("{\"message\":\"done\"}")
        ])
        let client = OurGroceriesAPIClient(transport: transport)
        try await client.signIn(email: "a", password: "b")
        await XCTAssertThrowsErrorAsync(try await client.insertItem(listID: "l", value: "Milk")) { error in
            XCTAssertEqual(error as? OurGroceriesAPIError, .insertionNotAcknowledged)
        }
    }

    func testHTMLCommandReplyIsRejected() async throws {
        let transport = FixtureTransport(replies: [.html("ok"), .html("<script>g_teamId='t'</script>"), .html("<html>sign in</html>")])
        let client = OurGroceriesAPIClient(transport: transport)
        try await client.signIn(email: "a", password: "b")
        await XCTAssertThrowsErrorAsync(try await client.overview()) { error in
            XCTAssertEqual(error as? OurGroceriesAPIError, .incompatibleResponse("command returned non-JSON content"))
        }
    }

    func testInspectAndInsertUseExpectedPayloadAndAcceptAcknowledgement() async throws {
        let transport = FixtureTransport(replies: [
            .html("ok"),
            .html("<script>let g_teamId = 'team'</script>"),
            .json("{\"list\":{\"items\":[{\"id\":\"item-1\",\"value\":\"Milk\",\"note\":null}]}}"),
            .json("{\"success\":true,\"itemId\":\"item-2\"}")
        ])
        let client = OurGroceriesAPIClient(transport: transport)
        try await client.signIn(email: "a", password: "b")
        let inspection = try await client.inspectList(id: "list-1")
        XCTAssertEqual(inspection.items, [GroceryItem(id: "item-1", value: "Milk", note: nil)])
        let acknowledgement = try await client.insertItem(listID: "list-1", value: "Eggs")
        XCTAssertEqual(acknowledgement.itemID, "item-2")
        let requests = await transport.requests
        let inspect = try XCTUnwrap(requests[2].httpBody).jsonObject() as! [String: Any]
        let insert = try XCTUnwrap(requests[3].httpBody).jsonObject() as! [String: Any]
        XCTAssertEqual(inspect["command"] as? String, "getList")
        XCTAssertEqual(inspect["listId"] as? String, "list-1")
        XCTAssertEqual(insert["command"] as? String, "insertItem")
        XCTAssertEqual(insert["value"] as? String, "Eggs")
        XCTAssertTrue(insert["note"] is NSNull)
    }
}

private actor FixtureTransport: HTTPTransport {
    enum Reply { case html(String); case json(String) }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        let reply = replies.removeFirst()
        let (text, type): (String, String) = switch reply { case .html(let text): (text, "text/html"); case .json(let text): (text, "application/json") }
        return HTTPResponse(data: Data(text.utf8), response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!)
    }
}

private extension Data {
    func jsonObject() throws -> Any { try JSONSerialization.jsonObject(with: self) }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, _ handler: (Error) -> Void) async {
    do { _ = try await expression(); XCTFail("expected error") } catch { handler(error) }
}
