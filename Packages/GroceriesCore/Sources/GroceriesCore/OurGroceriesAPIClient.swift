import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ShoppingList: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct GroceryItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let value: String
    public let note: String?
    public init(id: String, value: String, note: String?) { self.id = id; self.value = value; self.note = note }
}

public struct ListInspection: Codable, Sendable, Equatable {
    public let listID: String
    public let items: [GroceryItem]
}

public struct InsertAcknowledgement: Codable, Sendable, Equatable {
    public let itemID: String?
}

public enum OurGroceriesAPIError: Error, Sendable, Equatable {
    case invalidOrigin
    case invalidCredentials
    case authenticationRequired
    case unexpectedStatus(Int)
    case incompatibleResponse(String)
    case insertionNotAcknowledged
}

/// Narrow, fixed-origin implementation of the commands used by the menubar app.
/// It intentionally has no API for arbitrary hosts, headers, or downloaded code.
public actor OurGroceriesAPIClient {
    public static let origin = URL(string: "https://www.ourgroceries.com")!
    private let transport: any HTTPTransport
    private var teamID: String?
    private var staticMetalist: String?

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func signIn(email: String, password: String) async throws {
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "emailAddress", value: email),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: "sign-in")
        ]
        var request = try fixedRequest(path: "/sign-in", method: "POST")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let response = try await transport.send(request)
        try validateStatus(response.response, isLogin: true)
        let bootstrap = try await getBootstrap()
        teamID = bootstrap.teamID
        staticMetalist = bootstrap.staticMetalist
    }

    public func signOut() {
        teamID = nil
        staticMetalist = nil
        (transport as? URLSessionTransport)?.clearSession()
    }

    public func overview() async throws -> [ShoppingList] {
        let json = try await command("getOverview", extra: [:])
        let lists = JSONShape.findListDictionaries(in: json).compactMap { dictionary -> ShoppingList? in
            guard let id = JSONShape.string(dictionary["listId"] ?? dictionary["id"]),
                  let name = JSONShape.string(dictionary["name"] ?? dictionary["value"]) else { return nil }
            return ShoppingList(id: id, name: name)
        }
        guard !lists.isEmpty else { throw OurGroceriesAPIError.incompatibleResponse("overview contains no recognizable lists") }
        return Array(Dictionary(grouping: lists, by: \.id).values.compactMap(\.first))
    }

    public func inspectList(id listID: String) async throws -> ListInspection {
        let json = try await command("getList", extra: ["listId": listID])
        let itemDictionaries = JSONShape.findDictionaries(in: json).filter { dictionary in
            JSONShape.string(dictionary["value"]) != nil && (dictionary["id"] != nil || dictionary["itemId"] != nil)
        }
        let items = itemDictionaries.compactMap { dictionary -> GroceryItem? in
            guard let id = JSONShape.string(dictionary["itemId"] ?? dictionary["id"]),
                  let value = JSONShape.string(dictionary["value"]) else { return nil }
            return GroceryItem(id: id, value: value, note: JSONShape.string(dictionary["note"]))
        }
        return ListInspection(listID: listID, items: items)
    }

    @discardableResult
    public func insertItem(listID: String, value: String, note: String? = nil) async throws -> InsertAcknowledgement {
        let json = try await command("insertItem", extra: ["listId": listID, "value": value, "note": note ?? NSNull()])
        guard JSONShape.isPositiveAcknowledgement(json) else { throw OurGroceriesAPIError.insertionNotAcknowledged }
        return InsertAcknowledgement(itemID: JSONShape.firstString(in: json, keys: ["itemId", "id"]))
    }

    private func getBootstrap() async throws -> Bootstrap {
        let request = try fixedRequest(path: "/your-lists/", method: "GET")
        let reply = try await transport.send(request)
        try validateStatus(reply.response, isLogin: false)
        guard let html = String(data: reply.data, encoding: .utf8) else {
            throw OurGroceriesAPIError.incompatibleResponse("bootstrap is not UTF-8")
        }
        return try Bootstrap.parse(html: html)
    }

    private func command(_ name: String, extra: [String: Any]) async throws -> Any {
        guard let teamID else { throw OurGroceriesAPIError.authenticationRequired }
        var payload: [String: Any] = ["command": name, "teamId": teamID]
        for (key, value) in extra { payload[key] = value }
        var request = try fixedRequest(path: "/your-lists/", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        let reply = try await transport.send(request)
        try validateStatus(reply.response, isLogin: false)
        guard reply.response.mimeType?.lowercased().contains("json") == true else {
            throw OurGroceriesAPIError.incompatibleResponse("command returned non-JSON content")
        }
        do { return try JSONSerialization.jsonObject(with: reply.data, options: []) }
        catch { throw OurGroceriesAPIError.incompatibleResponse("command returned malformed JSON") }
    }

    private func fixedRequest(path: String, method: String) throws -> URLRequest {
        guard path.hasPrefix("/"), let url = URL(string: path, relativeTo: Self.origin),
              url.scheme == "https", url.host == Self.origin.host else { throw OurGroceriesAPIError.invalidOrigin }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("OurGroceriesApp/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validateStatus(_ response: HTTPURLResponse, isLogin: Bool) throws {
        if (200..<300).contains(response.statusCode) { return }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw isLogin ? OurGroceriesAPIError.invalidCredentials : OurGroceriesAPIError.authenticationRequired
        }
        throw OurGroceriesAPIError.unexpectedStatus(response.statusCode)
    }
}

private struct Bootstrap {
    let teamID: String
    let staticMetalist: String?

    static func parse(html: String) throws -> Bootstrap {
        guard let teamID = JavaScriptAssignment.value(named: "g_teamId", in: html), !teamID.isEmpty else {
            throw OurGroceriesAPIError.incompatibleResponse("bootstrap missing g_teamId")
        }
        return Bootstrap(teamID: teamID, staticMetalist: JavaScriptAssignment.value(named: "g_staticMetalist", in: html))
    }
}

private enum JavaScriptAssignment {
    static func value(named name: String, in html: String) -> String? {
        let pattern = "(?:var|let|const)?\\s*" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*([\"'])(.*?)\\1"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 2), in: html) else { return nil }
        return html[range].replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\'", with: "'")
    }
}

private enum JSONShape {
    static func string(_ value: Any?) -> String? { value as? String }

    static func findDictionaries(in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] { return [dictionary] + dictionary.values.flatMap(findDictionaries) }
        if let array = value as? [Any] { return array.flatMap(findDictionaries) }
        return []
    }

    static func findListDictionaries(in value: Any) -> [[String: Any]] {
        findDictionaries(in: value).filter { $0["listId"] != nil || ($0["id"] != nil && ($0["name"] != nil || $0["value"] != nil)) }
    }

    static func firstString(in value: Any, keys: Set<String>) -> String? {
        findDictionaries(in: value).lazy.compactMap { dictionary in keys.lazy.compactMap { string(dictionary[$0]) }.first }.first
    }

    static func isPositiveAcknowledgement(_ value: Any) -> Bool {
        guard let dictionary = value as? [String: Any] else { return false }
        if dictionary["success"] as? Bool == true { return true }
        if let result = string(dictionary["result"])?.lowercased(), ["success", "ok"].contains(result) { return true }
        if let status = string(dictionary["status"])?.lowercased(), ["success", "ok"].contains(status) { return true }
        return dictionary["itemId"] != nil
    }
}
