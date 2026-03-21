import Foundation
import CommonCrypto
import Security
import UIKit

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

// MARK: - OAuth 1.0a Signer
struct OAuth1Signer {
    let consumerKey: String
    let consumerSecret: String
    let accessToken: String
    let accessSecret: String

    /// Sign a request with OAuth 1.0a HMAC-SHA1
    func sign(request: inout URLRequest) {
        guard let url = request.url else { return }
        let method = request.httpMethod ?? "GET"
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let timestamp = String(Int(Date().timeIntervalSince1970))

        var oauthParams: [String: String] = [
            "oauth_consumer_key": consumerKey,
            "oauth_nonce": nonce,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": timestamp,
            "oauth_token": accessToken,
            "oauth_version": "1.0",
        ]

        // Collect all parameters (OAuth + query + POST body form params)
        var allParams = oauthParams
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                allParams[item.name] = item.value ?? ""
            }
        }
        // For POST with application/x-www-form-urlencoded
        if method == "POST",
           let contentType = request.value(forHTTPHeaderField: "Content-Type"),
           contentType.contains("application/x-www-form-urlencoded"),
           let body = request.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            let bodyParams = bodyString.components(separatedBy: "&")
            for param in bodyParams {
                let parts = param.components(separatedBy: "=")
                if parts.count == 2 {
                    allParams[parts[0].removingPercentEncoding ?? parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
                }
            }
        }

        // Build base string
        let baseURL = url.absoluteString.components(separatedBy: "?").first ?? url.absoluteString
        let sortedParams = allParams.sorted { $0.key < $1.key }
        let paramString = sortedParams.map { "\(percentEncode($0.key))=\(percentEncode($0.value))" }.joined(separator: "&")
        let baseString = "\(method)&\(percentEncode(baseURL))&\(percentEncode(paramString))"

        // Sign
        let signingKey = "\(percentEncode(consumerSecret))&\(percentEncode(accessSecret))"
        let signature = hmacSHA1(key: signingKey, data: baseString)
        oauthParams["oauth_signature"] = signature

        // Build Authorization header
        let authHeader = "OAuth " + oauthParams.sorted { $0.key < $1.key }
            .map { "\(percentEncode($0.key))=\"\(percentEncode($0.value))\"" }
            .joined(separator: ", ")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }

    private func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private func hmacSHA1(key: String, data: String) -> String {
        let keyData = key.data(using: .utf8)!
        let dataData = data.data(using: .utf8)!
        var result = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyBytes in
            dataData.withUnsafeBytes { dataBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
                        keyBytes.baseAddress, keyData.count,
                        dataBytes.baseAddress, dataData.count,
                        &result)
            }
        }
        return Data(result).base64EncodedString()
    }
}

// MARK: - Wikimedia Auth Manager
@Observable
class WikimediaAuth {
    static let shared = WikimediaAuth()

    var isLoggedIn: Bool { accessToken != nil }
    var username: String?

    private var consumerKey: String?
    private var consumerSecret: String?
    private var accessToken: String?
    private var accessSecret: String?

    private init() {
        consumerKey = KeychainHelper.load(key: "oauth_consumer_key")
        consumerSecret = KeychainHelper.load(key: "oauth_consumer_secret")
        accessToken = KeychainHelper.load(key: "oauth_access_token")
        accessSecret = KeychainHelper.load(key: "oauth_access_secret")
        username = UserDefaults.standard.string(forKey: "oauth_username")
    }

    /// Store OAuth tokens (called after registration)
    func storeTokens(consumerKey: String, consumerSecret: String, accessToken: String, accessSecret: String) {
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.accessToken = accessToken
        self.accessSecret = accessSecret

        KeychainHelper.save(key: "oauth_consumer_key", value: consumerKey)
        KeychainHelper.save(key: "oauth_consumer_secret", value: consumerSecret)
        KeychainHelper.save(key: "oauth_access_token", value: accessToken)
        KeychainHelper.save(key: "oauth_access_secret", value: accessSecret)

        fetchUsername()
    }

    /// Logout — clear all tokens
    func logout() {
        consumerKey = nil
        consumerSecret = nil
        accessToken = nil
        accessSecret = nil
        username = nil

        KeychainHelper.delete(key: "oauth_consumer_key")
        KeychainHelper.delete(key: "oauth_consumer_secret")
        KeychainHelper.delete(key: "oauth_access_token")
        KeychainHelper.delete(key: "oauth_access_secret")
        UserDefaults.standard.removeObject(forKey: "oauth_username")
    }

    /// Get a configured OAuth signer
    private var signer: OAuth1Signer? {
        guard let ck = consumerKey, let cs = consumerSecret,
              let at = accessToken, let as_ = accessSecret else { return nil }
        return OAuth1Signer(consumerKey: ck, consumerSecret: cs, accessToken: at, accessSecret: as_)
    }

    // MARK: - Fetch Username
    func fetchUsername() {
        guard let signer = signer else { return }

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
        request.setValue("VASturkiye/1.0", forHTTPHeaderField: "User-Agent")
        signer.sign(request: &request)

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

    // MARK: - Upload File to Commons

    /// Upload a photo to Wikimedia Commons
    /// - Parameters:
    ///   - imageData: JPEG data of the image
    ///   - fileName: Target filename on Commons
    ///   - wikitext: Full wikitext (description, license, categories)
    ///   - comment: Upload comment
    ///   - completion: Result with filename or error
    func uploadFile(
        imageData: Data,
        fileName: String,
        wikitext: String,
        comment: String,
        onProgress: @escaping (Double) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let signer = signer else {
            completion(.failure(AuthError.notLoggedIn))
            return
        }

        // Step 1: Get CSRF token
        fetchCSRFToken(signer: signer) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let csrfToken):
                // Step 2: Upload with token
                self.performUpload(
                    signer: signer,
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

    private func fetchCSRFToken(signer: OAuth1Signer, site: String = "https://commons.wikimedia.org", completion: @escaping (Result<String, Error>) -> Void) {
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
        request.setValue("VASturkiye/1.0", forHTTPHeaderField: "User-Agent")
        signer.sign(request: &request)

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

    private func performUpload(
        signer: OAuth1Signer,
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
        request.setValue("VASturkiye/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120

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

        // Sign (OAuth header only, not the multipart body)
        // For multipart, we sign without body params
        signer.sign(request: &request)

        // Use URLSession delegate for progress
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
    /// Sets a string claim on a Wikidata entity (e.g. P18 image filename)
    func setWikidataClaim(
        entityId: String,
        property: String,
        value: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let signer = signer else {
            completion(.failure(AuthError.notLoggedIn))
            return
        }

        // Step 1: Get CSRF token from Wikidata (same OAuth tokens work across all Wikimedia sites)
        fetchCSRFToken(signer: signer, site: "https://www.wikidata.org") { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let csrfToken):
                // Step 2: Use wbcreateclaim to add a new claim
                // Use multipart/form-data so OAuth signer doesn't include body params in signature
                let boundary = "Boundary-\(UUID().uuidString)"
                let url = URL(string: "https://www.wikidata.org/w/api.php")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.setValue("VASturkiye/1.0", forHTTPHeaderField: "User-Agent")

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

                signer.sign(request: &request)

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
