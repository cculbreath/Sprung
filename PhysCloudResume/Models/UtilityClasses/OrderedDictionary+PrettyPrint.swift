import OrderedCollections

extension OrderedDictionary {
    func prettyPrint() -> String {
        var result = "OrderedDictionary Contents:\n"
        for (index, (key, value)) in enumerated() {
            let valueType = type(of: value)
            result += "\(index + 1). Key: '\(key)' -> Value: '\(value)' (Type: \(valueType))\n"
        }
        return result
    }
}
