import Foundation
import CommonCrypto
import Security
import UIKit
import AuthenticationServices

// MARK: - Keychain Helper
struct KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.vasturkiye.oauth",
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.vasturkiye.oauth",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.vasturkiye.oauth",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - PKCE Helper
struct PKCEHelper {
    let codeVerifier: String
    let codeChallenge: String

    init() {
        // Generate a random 43-128 character code verifier
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        codeVerifier = Data(buffer)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // SHA256 hash of the verifier → base64url
        let verifierData = codeVerifier.data(using: .ascii)!
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        verifierData.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(verifierData.count), &hash)
        }
        codeChallenge = Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Wikimedia Auth Manager (OAuth 2.0)
@Observable
class WikimediaAuth {
    static let shared = WikimediaAuth()

    // OAuth 2.0 client ID (public, non-confidential — no secret needed)
    static let clientID = "0800eac6605bda2d9b15cba80a00ba9c"
    static let redirectURI = "https://sadrettin86.github.io/WLMTurkey/oauth-callback"
    static let authorizeURL = "https://meta.wikimedia.org/w/rest.php/oauth2/authorize"
    static let tokenURL = "https://meta.wikimedia.org/w/rest.php/oauth2/access_token"

    var isLoggedIn: Bool { accessToken != nil }
    var username: String?
    var isLoggingIn = false

    private var accessToken: String?
    private var refreshToken: String?
    private var pkce: PKCEHelper?
    private var authSession: ASWebAuthenticationSession?

    private init() {
        accessToken = KeychainHelper.load(key: "oauth2_access_token")
        refreshToken = KeychainHelper.load(key: "oauth2_refresh_token")
        username = UserDefaults.standard.string(forKey: "oauth_username")
    }

    // MARK: - Login Flow

    /// Start OAuth 2.0 + PKCE login flow
    func login(from anchor: ASWebAuthenticationPresentationContextProviding) {
        isLoggingIn = true
        let pkce = PKCEHelper()
        self.pkce = pkce

        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let authURL = components.url else {
            isLoggingIn = false
            return
        }

        // ASWebAuthenticationSession handles the browser → callback flow
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "wlmturkey"
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("OAuth login error: \(error.localizedDescription)")
                    self.isLoggingIn = false
                    return
                }
                guard let callbackURL = callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.isLoggingIn = false
                    return
                }
                self.exchangeCodeForToken(code: code)
            }
        }
        session.presentationContextProvider = anchor
        session.prefersEphemeralWebBrowserSession = false
        self.authSession = session
        session.start()
    }

    /// Exchange authorization code for access token
    private func exchangeCodeForToken(code: String) {
        guard let pkce = pkce else {
            isLoggingIn = false
            return
        }

        let url = URL(string: Self.tokenURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")

        let params = [
            "grant_type=authorization_code",
            "code=\(percentEncode(code))",
            "client_id=\(percentEncode(Self.clientID))",
            "redirect_uri=\(percentEncode(Self.redirectURI))",
            "code_verifier=\(percentEncode(pkce.codeVerifier))",
        ].joined(separator: "&")

        request.httpBody = params.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pkce = nil

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let accessToken = json["access_token"] as? String else {
                    print("Token exchange failed")
                    if let data = data, let body = String(data: data, encoding: .utf8) {
                        print("Response: \(body)")
                    }
                    self.isLoggingIn = false
                    return
                }

                self.accessToken = accessToken
                KeychainHelper.save(key: "oauth2_access_token", value: accessToken)

                if let refreshToken = json["refresh_token"] as? String {
                    self.refreshToken = refreshToken
                    KeychainHelper.save(key: "oauth2_refresh_token", value: refreshToken)
                }

                self.isLoggingIn = false
                self.fetchUsername()
            }
        }.resume()
    }

    /// Refresh access token using refresh token
    func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let refreshToken = refreshToken else {
            completion(false)
            return
        }

        let url = URL(string: Self.tokenURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")

        let params = [
            "grant_type=refresh_token",
            "refresh_token=\(percentEncode(refreshToken))",
            "client_id=\(percentEncode(Self.clientID))",
        ].joined(separator: "&")

        request.httpBody = params.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion(false)
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let newAccessToken = json["access_token"] as? String else {
                    completion(false)
                    return
                }

                self.accessToken = newAccessToken
                KeychainHelper.save(key: "oauth2_access_token", value: newAccessToken)

                if let newRefreshToken = json["refresh_token"] as? String {
                    self.refreshToken = newRefreshToken
                    KeychainHelper.save(key: "oauth2_refresh_token", value: newRefreshToken)
                }

                completion(true)
            }
        }.resume()
    }

    /// Logout — clear all tokens
    func logout() {
        accessToken = nil
        refreshToken = nil
        username = nil

        KeychainHelper.delete(key: "oauth2_access_token")
        KeychainHelper.delete(key: "oauth2_refresh_token")
        UserDefaults.standard.removeObject(forKey: "oauth_username")
    }

    // MARK: - Authenticated Requests

    /// Add Bearer token to a request
    private func authorize(request: inout URLRequest) {
        guard let token = accessToken else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Fetch Username
    func fetchUsername() {
        guard accessToken != nil else { return }

        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "meta", value: "userinfo"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        authorize(request: &request)

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let userinfo = query["userinfo"] as? [String: Any],
                      let name = userinfo["name"] as? String else { return }
                self.username = name
                UserDefaults.standard.set(name, forKey: "oauth_username")
            }
        }.resume()
    }

    // MARK: - CSRF Token

    private func fetchCSRFToken(site: String = "https://commons.wikimedia.org", completion: @escaping (Result<String, Error>) -> Void) {
        guard accessToken != nil else {
            completion(.failure(AuthError.notLoggedIn))
            return
        }

        var components = URLComponents(string: "\(site)/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "meta", value: "tokens"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]
        guard let url = components.url else {
            completion(.failure(AuthError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        authorize(request: &request)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let query = json["query"] as? [String: Any],
                  let tokens = query["tokens"] as? [String: Any],
                  let csrf = tokens["csrftoken"] as? String else {
                DispatchQueue.main.async { completion(.failure(AuthError.tokenFetchFailed)) }
                return
            }
            DispatchQueue.main.async { completion(.success(csrf)) }
        }.resume()
    }

    // MARK: - Upload File to Commons

    func uploadFile(
        imageData: Data,
        fileName: String,
        wikitext: String,
        comment: String,
        onProgress: @escaping (Double) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard accessToken != nil else {
            completion(.failure(AuthError.notLoggedIn))
            return
        }

        fetchCSRFToken { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let csrfToken):
                self.performUpload(
                    csrfToken: csrfToken,
                    imageData: imageData,
                    fileName: fileName,
                    wikitext: wikitext,
                    comment: comment,
                    onProgress: onProgress,
                    completion: completion
                )
            }
        }
    }

    private func performUpload(
        csrfToken: String,
        imageData: Data,
        fileName: String,
        wikitext: String,
        comment: String,
        onProgress: @escaping (Double) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let boundary = "Boundary-\(UUID().uuidString)"
        let url = URL(string: "https://commons.wikimedia.org/w/api.php")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        authorize(request: &request)

        // Build multipart body
        var body = Data()
        let fields: [(String, String)] = [
            ("action", "upload"),
            ("filename", fileName),
            ("text", wikitext),
            ("comment", comment),
            ("format", "json"),
            ("formatversion", "2"),
            ("token", csrfToken),
            ("ignorewarnings", "1"),
        ]

        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let session = URLSession(configuration: .default, delegate: UploadProgressDelegate(onProgress: onProgress), delegateQueue: nil)
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(AuthError.uploadFailed("Invalid response")))
                    return
                }

                if let uploadResult = json["upload"] as? [String: Any],
                   let result = uploadResult["result"] as? String {
                    if result == "Success" {
                        let filename = uploadResult["filename"] as? String ?? fileName
                        completion(.success(filename))
                    } else if result == "Warning" {
                        let warnings = uploadResult["warnings"] as? [String: Any]
                        let msg = warnings?.keys.joined(separator: ", ") ?? "Unknown warning"
                        completion(.failure(AuthError.uploadFailed("Warning: \(msg)")))
                    } else {
                        completion(.failure(AuthError.uploadFailed("Result: \(result)")))
                    }
                } else if let error = json["error"] as? [String: Any],
                          let info = error["info"] as? String {
                    completion(.failure(AuthError.uploadFailed(info)))
                } else {
                    completion(.failure(AuthError.uploadFailed("Unknown error")))
                }
            }
        }.resume()
    }

    // MARK: - Set Wikidata Claim (P18)

    func setWikidataClaim(
        entityId: String,
        property: String,
        value: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard accessToken != nil else {
            completion(.failure(AuthError.notLoggedIn))
            return
        }

        fetchCSRFToken(site: "https://www.wikidata.org") { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let csrfToken):
                let boundary = "Boundary-\(UUID().uuidString)"
                let url = URL(string: "https://www.wikidata.org/w/api.php")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
                self.authorize(request: &request)

                let fields: [(String, String)] = [
                    ("action", "wbcreateclaim"),
                    ("entity", entityId),
                    ("snaktype", "value"),
                    ("property", property),
                    ("value", "\"\(value)\""),
                    ("format", "json"),
                    ("formatversion", "2"),
                    ("token", csrfToken),
                    ("summary", "Added image via WLM Turkey app"),
                ]

                var body = Data()
                for (key, val) in fields {
                    body.append("--\(boundary)\r\n".data(using: .utf8)!)
                    body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                    body.append("\(val)\r\n".data(using: .utf8)!)
                }
                body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                request.httpBody = body

                URLSession.shared.dataTask(with: request) { data, _, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            completion(.failure(error))
                            return
                        }
                        guard let data = data,
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            completion(.failure(AuthError.uploadFailed("Invalid Wikidata response")))
                            return
                        }

                        if json["success"] as? Int == 1 {
                            completion(.success(()))
                        } else if let error = json["error"] as? [String: Any],
                                  let info = error["info"] as? String {
                            completion(.failure(AuthError.uploadFailed(info)))
                        } else {
                            completion(.failure(AuthError.uploadFailed("Unknown Wikidata error")))
                        }
                    }
                }.resume()
            }
        }
    }

    // MARK: - Helpers

    private func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    // MARK: - Errors
    enum AuthError: LocalizedError {
        case notLoggedIn
        case invalidURL
        case tokenFetchFailed
        case uploadFailed(String)

        var errorDescription: String? {
            switch self {
            case .notLoggedIn: return "Not logged in"
            case .invalidURL: return "Invalid URL"
            case .tokenFetchFailed: return "Failed to get CSRF token"
            case .uploadFailed(let msg): return msg
            }
        }
    }
}

// MARK: - Upload Progress Delegate
class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async {
            self.onProgress(progress)
        }
    }
}
