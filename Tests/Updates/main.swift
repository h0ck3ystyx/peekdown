import Foundation

func version(_ value: String) -> ReleaseVersion { ReleaseVersion(value)! }
precondition(version("1.0.9") < version("v1.0.10"))
precondition(version("1.1") == version("1.1.0+19"))
precondition(version("1.2.0-beta.1") < version("1.2.0"))
precondition(version("1.1.0") < version("1.2.0-dev"))
for invalid in ["", "v", "1..2", "1.2.3.4", "-1.0", "1.2/evil", "1.2.0-", "1.2.0+", "1.2.0+bad/thing", String(repeating:"9", count:80)] {
    precondition(ReleaseVersion(invalid) == nil, "Accepted invalid version: \(invalid)")
}
func payload(tag: String = "v1.2.0", draft: Bool = false, prerelease: Bool = false) -> Data {
    try! JSONSerialization.data(withJSONObject: ["tag_name":tag, "draft":draft, "prerelease":prerelease,
                                                "body":"Release notes", "html_url":"https://attacker.invalid/"])
}
let release = try UpdateService.parse(payload())
precondition(release.pageURL.absoluteString == "https://github.com/h0ck3ystyx/peekdown/releases/tag/v1.2.0")
precondition(release.notes == "Release notes")
for data in [Data("{}".utf8), Data("not JSON".utf8), payload(draft:true), payload(prerelease:true), payload(tag:"v1.2.0-rc.1"), payload(tag:"../../evil"), Data(repeating:0,count:UpdateService.maxResponseBytes+1)] {
    do { _ = try UpdateService.parse(data); fatalError("Accepted invalid release") } catch {}
}

final class StubProtocol: URLProtocol {
    static var status = 200
    static var data = payload()
    static var error: Error?
    static var advertisedLength: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.url == UpdateService.endpoint)
        precondition(request.value(forHTTPHeaderField:"Authorization") == nil)
        if let error = Self.error { client?.urlProtocol(self, didFailWithError:error); return }
        var headers = ["Content-Type":"application/json"]
        if let length = Self.advertisedLength { headers["Content-Length"] = length }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url:request.url!, statusCode:Self.status, httpVersion:nil, headerFields:headers)!, cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self, didLoad:Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
func fetch(status: Int = 200, data: Data = payload(), error: Error? = nil, length: String? = nil) -> Result<AvailableRelease, Error> {
    StubProtocol.status = status; StubProtocol.data = data; StubProtocol.error = error; StubProtocol.advertisedLength = length
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    let done = DispatchSemaphore(value:0)
    var outcome: Result<AvailableRelease, Error>?
    let service = UpdateService { outcome = $0; done.signal() }
    service.start(configuration:config)
    precondition(done.wait(timeout:.now()+5) == .success, "Update request did not complete")
    return outcome!
}
if case .failure = fetch() { fatalError("Valid release failed") }
for status in [403,429] {
    guard case .failure(let error) = fetch(status:status), case UpdateFailure.rateLimited = error else { fatalError("Rate limit not handled") }
}
for status in [404,500,302] {
    guard case .failure = fetch(status:status) else { fatalError("HTTP failure not handled") }
}
for data in [Data("broken".utf8), Data(repeating:65,count:UpdateService.maxResponseBytes+1)] {
    guard case .failure = fetch(data:data) else { fatalError("Bad/large response not rejected") }
}
guard case .failure(let sizeError) = fetch(length:"9999999"), case UpdateFailure.tooLarge = sizeError else { fatalError("Content length not bounded") }
for code in [URLError.notConnectedToInternet, .timedOut] {
    guard case .failure(let error) = fetch(error:URLError(code)), (error as NSError).code == code.rawValue else { fatalError("Network error lost") }
}
// Fresh requests still succeed after failures (manual retry).
if case .failure = fetch() { fatalError("Retry failed") }
print("Passed update checks: numeric versions, stable releases, trusted links, HTTP/network errors, byte limits, and retry")
let redirectService = UpdateService { _ in fatalError("Unexpected completion") }
let redirectResponse = HTTPURLResponse(url:UpdateService.endpoint, statusCode:302, httpVersion:nil, headerFields:["Location":"https://attacker.invalid/"])!
var refusedRedirect = false
redirectService.urlSession(URLSession.shared, task:URLSession.shared.dataTask(with:UpdateService.endpoint), willPerformHTTPRedirection:redirectResponse, newRequest:URLRequest(url:URL(string:"https://attacker.invalid/")!)) { refusedRedirect = $0 == nil }
precondition(refusedRedirect)
print("Passed redirect refusal")
