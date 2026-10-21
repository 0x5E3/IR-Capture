import Foundation

/// Minimal ordered JSON value, so report.json keeps the same key order and nulls as the page.
public indirect enum JSON {
    case null
    case bool(Bool)
    case int(Int)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([(String, JSON)])

    public static func opt(_ v: Double?) -> JSON { v.map { .number($0) } ?? .null }

    public func serialized(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent), pad1 = String(repeating: "  ", count: indent + 1)
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .number(let d): return JSON.formatNumber(d)
        case .string(let s): return JSON.quote(s)
        case .array(let a):
            if a.isEmpty { return "[]" }
            return "[\n" + a.map { pad1 + $0.serialized(indent: indent + 1) }.joined(separator: ",\n") + "\n" + pad + "]"
        case .object(let o):
            if o.isEmpty { return "{}" }
            return "{\n" + o.map { pad1 + JSON.quote($0.0) + ": " + $0.1.serialized(indent: indent + 1) }.joined(separator: ",\n") + "\n" + pad + "}"
        }
    }

    static func formatNumber(_ d: Double) -> String {
        if !d.isFinite { return "null" }
        if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
        return "\(d)"
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }
}
