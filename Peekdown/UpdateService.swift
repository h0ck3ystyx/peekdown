import Foundation

/// Numeric release ordering; experimental installs never get a numeric downgrade.
struct ReleaseVersion: Comparable {
    let numbers: [Int]
    let prerelease: Bool
    init?(_ raw: String) {
        let value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        guard value.utf8.count <= 100 else { return nil }
        let parts = value.split(separator: "+", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        func validSuffix(_ text: Substring) -> Bool {
            !text.isEmpty && text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
            }
        }
        if parts.count == 2 && !validSuffix(parts[1]) { return nil }
        let core = parts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        if core.count == 2 && !validSuffix(core[1]) { return nil }
        let digits = core[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(digits.count), digits.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let values = digits.compactMap { Int($0) }
        guard values.count == digits.count else { return nil }
        numbers = values + Array(repeating: 0, count: 3 - values.count)
        prerelease = core.count == 2
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.numbers == rhs.numbers && lhs.prerelease == rhs.prerelease }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        return lhs.prerelease && !rhs.prerelease
    }
}

struct AvailableRelease {
    let version: ReleaseVersion
    let tag: String
    let notes: String
    // Construct the link from a validated tag; never open server-provided URLs.
    var pageURL: URL { URL(string: "https://github.com/h0ck3ystyx/peekdown/releases/tag/\(tag)")! }
}

enum UpdateFailure: Error, LocalizedError {
    case invalidResponse, rateLimited, unavailable, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "GitHub returned an unexpected release response. Please try again later."
        case .rateLimited: return "GitHub is limiting update requests. Please wait and try again later."
        case .unavailable: return "The release service is unavailable. Please try again later."
        case .tooLarge: return "The release response was too large. Please try again later."
        }
    }
}

/// Host-only, manual, unauthenticated request. No cookies, cache, or redirects.
final class UpdateService: NSObject, URLSessionDataDelegate {
    static let endpoint = URL(string: "https://api.github.com/repos/h0ck3ystyx/peekdown/releases/latest")!
    static let maxResponseBytes = 262_144
    private var session: URLSession?
    private var buffer = Data()
    private var failure: Error?
    private let completion: (Result<AvailableRelease, Error>) -> Void

    init(completion: @escaping (Result<AvailableRelease, Error>) -> Void) { self.completion = completion }

    func start(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Peekdown-Update-Check", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request).resume()
    }

    static func parse(_ data: Data) throws -> AvailableRelease {
        struct Response: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool; let body: String? }
        guard data.count <= maxResponseBytes,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              !response.draft, !response.prerelease,
              let version = ReleaseVersion(response.tag_name), !version.prerelease else { throw UpdateFailure.invalidResponse }
        return AvailableRelease(version: version, tag: response.tag_name, notes: String((response.body ?? "No release notes provided.").prefix(20_000)))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        failure = UpdateFailure.invalidResponse
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.url == Self.endpoint else {
            failure = UpdateFailure.invalidResponse; completionHandler(.cancel); return
        }
        guard http.statusCode == 200 else {
            failure = (http.statusCode == 403 || http.statusCode == 429) ? UpdateFailure.rateLimited : UpdateFailure.unavailable
            completionHandler(.cancel); return
        }
        guard response.expectedContentLength <= Int64(Self.maxResponseBytes) else {
            failure = UpdateFailure.tooLarge; completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard buffer.count + data.count <= Self.maxResponseBytes else {
            failure = UpdateFailure.tooLarge; dataTask.cancel(); return
        }
        buffer.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<AvailableRelease, Error>
        if let error = failure ?? error { result = .failure(error) }
        else { result = Result { try Self.parse(buffer) } }
        session.finishTasksAndInvalidate()
        self.session = nil
        completion(result)
    }
}
