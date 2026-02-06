import Foundation

private var locBundle: Bundle {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle.main
    #endif
}

public func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: locBundle, comment: "")
}

public func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: locBundle, comment: "")
    return String(format: format, arguments: args)
}
