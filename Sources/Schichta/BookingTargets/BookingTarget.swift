import Foundation
import Security

// MARK: - Booking Targets (deklarative HTTP-Ziele)
//
// Jede *.json in ~/Library/Application Support/Schichta/targets beschreibt ein Ziel:
// wohin (method/url), wie authentifiziert (auth; der Wert liegt im Schlüsselbund, in der
// Datei steht nur sein Name) und welcher JSON-Body aus unseren Feldern gebaut wird
// (Platzhalter wie {{entry.ticket}}). Die App kennt kein Zielsystem; neue Systeme = neue Datei.

enum TargetMode: String {
    case perEntry, perDay
}

enum TargetAuth: Equatable {
    case none
    case bearer(secret: String)
    case basic(username: String, secret: String)
    case header(name: String, secret: String)

    var secretName: String? {
        switch self {
        case .none: return nil
        case .bearer(let s), .basic(_, let s), .header(_, let s): return s
        }
    }
}

struct BookingTarget {
    let id: String
    let name: String
    let method: String
    let url: String
    let mode: TargetMode
    let auth: TargetAuth
    let headers: [String: String]
    let body: Any?
    let map: [String: String]

    static func parse(id: String, data: Data) throws -> BookingTarget {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SchichtaError("Datei muss ein JSON-Objekt sein.")
        }
        guard let url = obj["url"] as? String, !url.isEmpty else { throw SchichtaError("\"url\" fehlt.") }
        let method = (obj["method"] as? String ?? "POST").uppercased()
        guard ["POST", "PUT", "PATCH"].contains(method) else { throw SchichtaError("\"method\" muss POST, PUT oder PATCH sein.") }
        guard let mode = TargetMode(rawValue: obj["mode"] as? String ?? "perEntry") else {
            throw SchichtaError("\"mode\" muss perEntry oder perDay sein.")
        }

        let authObj = obj["auth"] as? [String: Any] ?? ["type": "none"]
        // Schutz vor Klartext-Secrets in der Datei: nur der Name gehört hierher.
        if authObj.keys.contains(where: { ["value", "token", "password", "key", "apiKey"].contains($0) }) {
            throw SchichtaError("Secrets gehören nicht in die Datei. Unter \"secret\" nur einen Namen angeben und den Wert in Schichta im Schlüsselbund speichern.")
        }
        let secret = authObj["secret"] as? String ?? ""
        let auth: TargetAuth
        switch authObj["type"] as? String ?? "none" {
        case "none":
            auth = .none
        case "bearer" where !secret.isEmpty:
            auth = .bearer(secret: secret)
        case "basic" where !secret.isEmpty:
            guard let user = authObj["username"] as? String, !user.isEmpty else { throw SchichtaError("auth.basic braucht \"username\".") }
            auth = .basic(username: user, secret: secret)
        case "header" where !secret.isEmpty:
            guard let header = authObj["header"] as? String, !header.isEmpty else { throw SchichtaError("auth.header braucht \"header\".") }
            auth = .header(name: header, secret: secret)
        default:
            throw SchichtaError("\"auth\" braucht type (none, bearer, basic, header) und einen \"secret\"-Namen.")
        }

        return BookingTarget(
            id: id,
            name: obj["name"] as? String ?? id,
            method: method,
            url: url,
            mode: mode,
            auth: auth,
            headers: obj["headers"] as? [String: String] ?? [:],
            body: obj["body"],
            map: obj["map"] as? [String: String] ?? [:]
        )
    }
}

struct PreparedRequest {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data
    let maskedHeaders: Set<String>
    let label: String

    /// Anzeige für die Vorschau; Auth-Header werden nie im Klartext gezeigt.
    var previewText: String {
        var lines = ["\(method) \(url.absoluteString)"]
        for key in headers.keys.sorted() {
            lines.append("\(key): \(maskedHeaders.contains(key) ? "••••••" : headers[key]!)")
        }
        if !body.isEmpty {
            lines.append("")
            lines.append(String(decoding: body, as: UTF8.self))
        }
        return lines.joined(separator: "\n")
    }
}

enum TargetRenderer {
    private static let placeholder = try! NSRegularExpression(pattern: #"\{\{\s*([A-Za-z0-9_.]+)\s*\}\}"#)

    /// Baut aus Ziel + Tageseinträgen die konkreten Requests. Rein, ohne Netzwerk – Grundlage für Vorschau und Senden.
    static func prepare(
        target: BookingTarget,
        day: String,
        entries: [Entry],
        author: String,
        workStart: (hour: Int, minute: Int),
        repos: [TrackedRepo],
        secret: (String) -> String?
    ) throws -> [PreparedRequest] {
        _ = try Activity.bounds(day) // validiert das Datum
        guard !entries.isEmpty else { throw SchichtaError("Keine Einträge für \(SchichtaCore.formatGermanDate(day)).") }

        // Schichta speichert nur Dauern: Start/Ende werden ab Arbeitsbeginn lückenlos hintereinander gelegt.
        guard var cursor = Berlin.calendar.date(bySettingHour: workStart.hour, minute: workStart.minute, second: 0, of: SchichtaCore.dateFromBerlinDay(day)) else {
            throw SchichtaError("Arbeitsbeginn ungültig.")
        }
        let iso = ISO8601DateFormatter() // UTC, z. B. 2026-10-26T08:00:00Z
        let hours: (Int) -> Double = { Double(Int((Double($0) / 60 * 100).rounded())) / 100 }

        let entryContexts: [[String: Any]] = entries.map { e in
            let start = cursor
            let end = start.addingTimeInterval(TimeInterval(e.minutes * 60))
            cursor = end
            return [
                "id": e.id, "date": e.date, "ticket": e.ticket, "description": e.description,
                "minutes": e.minutes, "hours": hours(e.minutes), "duration": SchichtaCore.formatTime(e.minutes),
                "estimated": e.estimated, "project": SchichtaCore.resolveProjectName(for: e, repos: repos),
                "start": iso.string(from: start), "end": iso.string(from: end),
                "startTime": Berlin.clock.string(from: start), "endTime": Berlin.clock.string(from: end)
            ]
        }
        let total = entries.reduce(0) { $0 + $1.minutes }
        let dayContext: [String: Any] = [
            "date": day, "dateFormatted": SchichtaCore.formatGermanDate(day), "author": author,
            "totalMinutes": total, "totalHours": hours(total), "totalDuration": SchichtaCore.formatTime(total),
            "entries": entryContexts
        ]

        var authHeader: (name: String, value: String)?
        if let name = target.auth.secretName {
            guard let value = secret(name), !value.isEmpty else {
                throw SchichtaError("Secret „\(name)“ fehlt im Schlüsselbund.")
            }
            switch target.auth {
            case .bearer: authHeader = ("Authorization", "Bearer \(value)")
            case .basic(let user, _): authHeader = ("Authorization", "Basic " + Data("\(user):\(value)".utf8).base64EncodedString())
            case .header(let header, _): authHeader = (header, value)
            case .none: break
            }
        }

        let contexts: [(context: [String: Any], label: String)] = target.mode == .perDay
            ? [(dayContext, "Tag \(SchichtaCore.formatGermanDate(day)) (\(entries.count) Einträge)")]
            : zip(entries, entryContexts).map { e, ec in
                (dayContext.merging(["entry": ec]) { $1 }, "\(e.ticket.isEmpty ? "" : e.ticket + " ")\(e.description)")
            }

        return try contexts.map { ctx, label in
            let encodePath: (String) -> String = {
                $0.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? $0
            }
            let urlString = try renderString(target.url, ctx, map: target.map, encode: encodePath) as? String ?? target.url
            guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
                throw SchichtaError("Ungültige URL: \(urlString)")
            }
            let isLocal = ["localhost", "127.0.0.1", "::1"].contains(host)
            guard scheme == "https" || (scheme == "http" && isLocal) else {
                throw SchichtaError("Nur https erlaubt (http nur für localhost): \(urlString)")
            }

            var headers: [String: String] = [:]
            for (key, value) in target.headers {
                headers[key] = try stringValue(try renderString(value, ctx, map: target.map), path: key)
            }
            var body = Data()
            if let template = target.body {
                let rendered = try render(template, ctx, map: target.map)
                guard JSONSerialization.isValidJSONObject(rendered) else {
                    throw SchichtaError("\"body\" muss ein JSON-Objekt oder eine Liste sein.")
                }
                body = try JSONSerialization.data(withJSONObject: rendered, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                if !headers.keys.contains(where: { $0.lowercased() == "content-type" }) {
                    headers["Content-Type"] = "application/json"
                }
            }
            var masked: Set<String> = []
            if let auth = authHeader {
                headers[auth.name] = auth.value
                masked.insert(auth.name)
            }
            return PreparedRequest(method: target.method, url: url, headers: headers, body: body, maskedHeaders: masked, label: label)
        }
    }

    static func render(_ template: Any, _ ctx: [String: Any], map: [String: String]) throws -> Any {
        switch template {
        case let s as String: return try renderString(s, ctx, map: map)
        case let d as [String: Any]: return try d.mapValues { try render($0, ctx, map: map) }
        case let a as [Any]: return try a.map { try render($0, ctx, map: map) }
        default: return template // Zahlen, Bool, null bleiben unverändert
        }
    }

    /// Ist der ganze String ein Platzhalter, bleibt der Typ erhalten (Zahl bleibt Zahl, Liste bleibt Liste);
    /// sonst werden die Werte als Text eingesetzt.
    static func renderString(_ s: String, _ ctx: [String: Any], map: [String: String], encode: ((String) -> String)? = nil) throws -> Any {
        let ns = s as NSString
        let matches = placeholder.matches(in: s, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return s }
        if encode == nil, matches.count == 1, matches[0].range.length == ns.length {
            return try lookup(ns.substring(with: matches[0].range(at: 1)), ctx, map: map)
        }
        var result = ""
        var last = 0
        for m in matches {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let path = ns.substring(with: m.range(at: 1))
            let text = try stringValue(try lookup(path, ctx, map: map), path: path)
            result += encode?(text) ?? text
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func lookup(_ path: String, _ ctx: [String: Any], map: [String: String]) throws -> Any {
        let parts = path.split(separator: ".").map(String.init)
        // {{map.ticket}}: Wert des Eintragsfelds über die "map"-Tabelle der Zieldatei übersetzen.
        if parts.count == 2, parts[0] == "map" {
            let key = try stringValue(try lookup("entry." + parts[1], ctx, map: map), path: path)
            guard let mapped = map[key] else { throw SchichtaError("Keine Zuordnung in \"map\" für „\(key)“ ({{\(path)}}).") }
            return mapped
        }
        var current: Any = ctx
        for part in parts {
            guard let dict = current as? [String: Any], let next = dict[part] else {
                throw SchichtaError("Unbekannter Platzhalter {{\(path)}}.")
            }
            current = next
        }
        return current
    }

    static func stringValue(_ value: Any, path: String) throws -> String {
        switch value {
        case let s as String: return s
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return String(i)
        case let d as Double: return d == d.rounded() ? String(Int(d)) : String(d)
        default: throw SchichtaError("{{\(path)}} ist eine Liste/ein Objekt und kann nicht in Text eingesetzt werden.")
        }
    }
}

/// Secrets der Ziele im Login-Schlüsselbund (Dienst „Schichta.Targets“, Konto = Secret-Name).
enum TargetSecrets {
    private static let service = "Schichta.Targets"

    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name]
    }

    static func get(_ name: String) -> String? {
        var q = query(name)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Prüft nur, ob ein Eintrag existiert, ohne den Wert zu lesen (kein Schlüsselbund-Dialog).
    static func exists(_ name: String) -> Bool {
        var q = query(name)
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func set(_ name: String, _ value: String) -> Bool {
        SecItemDelete(query(name) as CFDictionary)
        var q = query(name)
        q[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}

final class TargetSender: NSObject, URLSessionTaskDelegate {
    struct Result {
        let ok: Bool
        let line: String
    }

    // Keinen Weiterleitungen folgen: sonst könnte der Auth-Header an einen fremden Host gehen.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func send(_ requests: [PreparedRequest]) async -> [Result] {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var results: [Result] = []
        for prepared in requests {
            var request = URLRequest(url: prepared.url, timeoutInterval: 20)
            request.httpMethod = prepared.method
            for (key, value) in prepared.headers { request.setValue(value, forHTTPHeaderField: key) }
            if !prepared.body.isEmpty { request.httpBody = prepared.body }
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let ok = (200..<300).contains(status)
                let detail = ok ? "" : " · " + String(decoding: data.prefix(300), as: UTF8.self)
                results.append(Result(ok: ok, line: "\(ok ? "✓" : "✗") \(status) · \(prepared.label)\(detail)"))
            } catch {
                results.append(Result(ok: false, line: "✗ \(prepared.label) · \(error.localizedDescription)"))
            }
        }
        return results
    }
}
