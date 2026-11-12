import Foundation

public enum AspectSizing {
    public static func validate(width: Int, height: Int, pixelMax: Int) throws {
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= pixelMax else {
            throw MetaPromptError("Resolution \(width)*\(height) uses \(overflow ? "too many" : String(pixels)) pixels, exceeding pixel_max=\(pixelMax). Raise pixel_max or choose a smaller resolution.")
        }
    }
    public static func resolve(_ text: String, pixelMax: Int) throws -> (width: Int, height: Int, aspect: String) {
        let parts = text.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              parts.allSatisfy({ $0.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil }),
              let a = Int(parts[0]), let b = Int(parts[1]), a > 0, b > 0 else {
            throw MetaPromptError("aspect must be two positive integers, for example 9:7 or 16:9.")
        }
        var x = a, y = b
        while y != 0 { let remainder = x % y; x = y; y = remainder }
        let p = a / x, q = b / x
        let axisLimit = Int(UInt16.max)
        guard p <= axisLimit, q <= axisLimit else {
            throw MetaPromptError("Aspect \(p):\(q) cannot be represented within the supported 64-pixel dimensions.")
        }
        // All exact grid-compatible sizes are (64*p*k, 64*q*k).
        // These products fit Int64 once p/q are bounded by UInt16.max.
        let basePixels = 4096 * p * q
        let available = pixelMax / basePixels
        var low = 1, high = min(axisLimit / p, axisLimit / q), best = 0
        while low <= high {
            let middle = low + (high - low) / 2
            if middle * middle <= available { best = middle; low = middle + 1 }
            else { high = middle - 1 }
        }
        guard best > 0 else {
            throw MetaPromptError("No exact 64-pixel size for aspect \(p):\(q) fits pixel_max=\(pixelMax). The smallest is \(64*p)*\(64*q) (\(basePixels) pixels).")
        }
        return (64 * p * best, 64 * q * best, "\(p):\(q)")
    }
}
