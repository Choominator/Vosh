import Foundation
import ApplicationServices

/// Declares the required functionality for any Swift type that can be converted to and from a CoreFoundation type.
protocol AccessibilityLegacyConvertible {
    /// CoreFoundation type.
    associatedtype LegacyType
    /// Initializes a new Swift type by converting from a legacy CoreFoundation type.
    init?(legacyValue value: CFTypeRef)
    /// Converts this Swift type to a legacy CoreFoundation type.
    var legacyValue: LegacyType {get}
}

extension Optional: AccessibilityLegacyConvertible where Wrapped: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) != CFNullGetTypeID() else {
            return nil
        }
        self = Wrapped(legacyValue: value)
    }

    var legacyValue: CFTypeRef {
        switch self {
        case .some(let value):
            return value.legacyValue as CFTypeRef
        case .none:
            return kCFNull
        }
    }
}

extension Bool: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }
        let boolean = unsafeBitCast(value, to: CFBoolean.self)
        self = CFBooleanGetValue(boolean)
    }

    var legacyValue: CFBoolean {
        return self ? kCFBooleanTrue : kCFBooleanFalse
    }
}

extension Int64: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == CFNumberGetTypeID() else {
            return nil
        }
        let number = unsafeBitCast(value, to: CFNumber.self)
        var integer = Int64(0)
        guard CFNumberGetValue(number, .sInt64Type, &integer) else {
            return nil
        }
        guard let integer = Self(exactly: integer) else {
            return nil
        }
        self = integer
    }

    var legacyValue: CFNumber {
        var integer = self
        return CFNumberCreate(nil, .sInt64Type, &integer)
    }
}

extension Double: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == CFNumberGetTypeID() else {
            return nil
        }
        let number = unsafeBitCast(value, to: CFNumber.self)
        var float = Double(0.0)
        guard CFNumberGetValue(number, .doubleType, &float) else {
            return nil
        }
        guard let float = Self(exactly: float) else {
            return nil
        }
        self = float
    }

    var legacyValue: CFNumber {
        var float = self
        return CFNumberCreate(nil, .doubleType, &float)
    }
}

extension String: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }
        self = unsafeBitCast(value, to: CFString.self) as String
    }

    var legacyValue: CFString {
        return self as CFString
    }
}

extension [Any?]: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == CFArrayGetTypeID() else {
            return nil
        }
        let array = unsafeBitCast(value, to: CFArray.self) as! Array
        self = Self()
        self.reserveCapacity(array.count)
        for element in array {
            self.append(fromLegacy(value: element as CFTypeRef))
        }
    }

    var legacyValue: CFArray {
        return self as CFArray
    }
}

extension [String: Any]: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == CFDictionaryGetTypeID() else {
            return nil
        }
        let dictionary = unsafeBitCast(value, to: CFDictionary.self) as! Self
        self = Self()
        self.reserveCapacity(dictionary.count)
        for pair in dictionary {
            guard let key = fromLegacy(value: pair.key as CFTypeRef) as? String, let value = fromLegacy(value: pair.value as CFTypeRef) else {
                continue
            }
            self[key] = value
        }
    }

    var legacyValue: CFDictionary {
        return self as CFDictionary
    }
}

extension URL: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == CFURLGetTypeID() else {
            return nil
        }
        let url = unsafeBitCast(value, to: CFURL.self)
        self = url as URL
    }

    var legacyValue: CFURL {
        return self as CFURL
    }
}

extension AttributedString: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == CFAttributedStringGetTypeID() else {
            return nil
        }
        let attributedString = unsafeBitCast(value, to: CFAttributedString.self) as NSAttributedString
        self = AttributedString(attributedString as NSAttributedString)
    }

    var legacyValue: CFAttributedString {
        return NSAttributedString(self) as CFAttributedString
    }
}

extension Range: AccessibilityLegacyConvertible where Bound == Int {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(value, to: AXValue.self)
        var range = CFRangeMake(0, 0)
        guard AXValueGetValue(value, .cfRange, &range) else {
            return nil
        }
        self = Int(range.location) ..< Int(range.location + range.length)
    }

    var legacyValue: AXValue {
        var range = CFRangeMake(self.lowerBound, self.upperBound - self.lowerBound)
        return AXValueCreate(.cfRange, &range)!
    }
}

extension CGPoint: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else {
            return nil
        }
        self = point
    }

    var legacyValue: AXValue {
        var point = self
        return AXValueCreate(.cgPoint, &point)!
    }
}

extension CGSize: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else {
            return nil
        }
        self = size
    }

    var legacyValue: AXValue {
        var size = self
        return AXValueCreate(.cgSize, &size)!
    }
}

extension CGRect: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(value, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect) else {
            return nil
        }
        self = rect
    }

    var legacyValue: AXValue {
        var rect = self
        return AXValueCreate(.cgRect, &rect)!
    }
}

extension AccessibilityError: AccessibilityLegacyConvertible {
    init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(value, to: AXValue.self)
        var error = AXError.success
        guard AXValueGetValue(value, .axError, &error) else {
            return nil
        }
        self = AccessibilityError(from: error)
    }

    var legacyValue: AXValue {
        var error = self.toAXError()
        return AXValueCreate(.axError, &error)!
    }
}

extension AccessibilityElement: AccessibilityLegacyConvertible {}

/// Converts a value from any known legacy type to a Swift type.
/// - Parameter value: Value to convert.
/// - Returns: Converted Swift value.
func fromLegacy(value: CFTypeRef?) -> Any? {
    guard let value = value else {
        return nil
    }
    guard CFGetTypeID(value) != CFNullGetTypeID() else {
        return nil
    }
    if let boolean = Bool(legacyValue: value) {
        return boolean
    }
    if let integer = Int64(legacyValue: value) {
        return integer
    }
    if let float = Double(legacyValue: value) {
        return float
    }
    if let string = String(legacyValue: value) {
        return string
    }
    if let array = [Any?](legacyValue: value) {
        return array
    }
    if let dictionary = [String: Any](legacyValue: value) {
        return dictionary
    }
    if let url = URL(legacyValue: value) {
        return url
    }
    if let attributedString = AttributedString(legacyValue: value) {
        return attributedString
    }
    if let range = Range(legacyValue: value) {
        return range
    }
    if let point = CGPoint(legacyValue: value) {
        return point
    }
    if let size = CGSize(legacyValue: value) {
        return size
    }
    if let rect = CGRect(legacyValue: value) {
        return rect
    }
    if let error = AccessibilityError(legacyValue: value) {
        return error
    }
    if let element = AccessibilityElement(legacyValue: value) {
        return element
    }
    return nil
}
