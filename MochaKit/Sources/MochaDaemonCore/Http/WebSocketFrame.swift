import Foundation

public enum WebSocketMessage: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

public struct WebSocketCloseCode: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let normalClosure = WebSocketCloseCode(rawValue: 1000)
    public static let goingAway = WebSocketCloseCode(rawValue: 1001)
    public static let protocolError = WebSocketCloseCode(rawValue: 1002)
    public static let unsupportedData = WebSocketCloseCode(rawValue: 1003)
    public static let invalidPayload = WebSocketCloseCode(rawValue: 1007)
    public static let policyViolation = WebSocketCloseCode(rawValue: 1008)
    public static let messageTooBig = WebSocketCloseCode(rawValue: 1009)
    public static let internalError = WebSocketCloseCode(rawValue: 1011)

    var isValidOnWire: Bool {
        switch rawValue {
        case 1000...1003, 1007...1014, 3000...4999: true
        default: false
        }
    }
}

enum WebSocketOpcode: UInt8, Sendable {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA

    var isControl: Bool {
        rawValue & 0x8 != 0
    }
}

struct WebSocketFrame: Sendable, Equatable {
    enum Decoding: Equatable {
        case incomplete
        case frame(WebSocketFrame, consumed: Int)
        case violation(WebSocketCloseCode)
    }

    enum ClosePayload: Equatable {
        case valid(WebSocketCloseCode?, String)
        case invalid(WebSocketCloseCode)
    }

    static let maxControlPayload = 125

    let isFinal: Bool
    let opcode: WebSocketOpcode
    let payload: [UInt8]

    static func decode(_ buffer: [UInt8], from start: Int, maxDataPayload: Int) -> Decoding {
        let available = buffer.count - start
        guard available >= 2 else { return .incomplete }
        let first = buffer[start]
        let second = buffer[start + 1]
        guard first & 0x70 == 0, let opcode = WebSocketOpcode(rawValue: first & 0x0F), second & 0x80 != 0 else {
            return .violation(.protocolError)
        }
        let isFinal = first & 0x80 != 0
        let shortLength = Int(second & 0x7F)
        if opcode.isControl, !isFinal || shortLength > maxControlPayload {
            return .violation(.protocolError)
        }
        let extendedLengthBytes = shortLength == 126 ? 2 : (shortLength == 127 ? 8 : 0)
        let headerLength = 2 + extendedLengthBytes + 4
        guard available >= headerLength else { return .incomplete }
        var payloadLength = shortLength
        if extendedLengthBytes > 0 {
            var value: UInt64 = 0
            for offset in 0..<extendedLengthBytes {
                value = value << 8 | UInt64(buffer[start + 2 + offset])
            }
            guard value >> 63 == 0 else { return .violation(.protocolError) }
            payloadLength = Int(value)
        }
        if !opcode.isControl, payloadLength > maxDataPayload {
            return .violation(.messageTooBig)
        }
        guard available - headerLength >= payloadLength else { return .incomplete }
        let maskStart = start + 2 + extendedLengthBytes
        let payloadStart = start + headerLength
        var payload = [UInt8](repeating: 0, count: payloadLength)
        for index in 0..<payloadLength {
            payload[index] = buffer[payloadStart + index] ^ buffer[maskStart + (index & 3)]
        }
        return .frame(
            WebSocketFrame(isFinal: isFinal, opcode: opcode, payload: payload),
            consumed: headerLength + payloadLength
        )
    }

    static func encode(_ opcode: WebSocketOpcode, payload: some Collection<UInt8>) -> Data {
        let count = payload.count
        var data = Data(capacity: count + 10)
        data.append(0x80 | opcode.rawValue)
        if count < 126 {
            data.append(UInt8(truncatingIfNeeded: count))
        } else if count <= 0xFFFF {
            data.append(126)
            data.append(UInt8(truncatingIfNeeded: count >> 8))
            data.append(UInt8(truncatingIfNeeded: count))
        } else {
            data.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                data.append(UInt8(truncatingIfNeeded: UInt64(count) >> UInt64(shift)))
            }
        }
        data.append(contentsOf: payload)
        return data
    }

    static func closePayload(code: WebSocketCloseCode, reason: String) -> [UInt8] {
        var payload = [UInt8(truncatingIfNeeded: code.rawValue >> 8), UInt8(truncatingIfNeeded: code.rawValue)]
        var reasonBytes: [UInt8] = []
        for scalar in reason.unicodeScalars {
            let encoded = Array(String(scalar).utf8)
            guard reasonBytes.count + encoded.count <= maxControlPayload - 2 else { break }
            reasonBytes.append(contentsOf: encoded)
        }
        payload.append(contentsOf: reasonBytes)
        return payload
    }

    static func parseClose(_ payload: [UInt8]) -> ClosePayload {
        guard !payload.isEmpty else { return .valid(nil, "") }
        guard payload.count >= 2 else { return .invalid(.protocolError) }
        let code = WebSocketCloseCode(rawValue: UInt16(payload[0]) << 8 | UInt16(payload[1]))
        guard code.isValidOnWire else { return .invalid(.protocolError) }
        guard let reason = String(validating: payload[2...], as: UTF8.self) else { return .invalid(.invalidPayload) }
        return .valid(code, reason)
    }
}
