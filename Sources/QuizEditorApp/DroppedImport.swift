import Foundation

/// Which importer a file dropped onto the window should go through. Matching is
/// by filename extension rather than `UTType` because `.imscc` and `.quizeditor`
/// are only declared in the app bundle's Info.plist, and a dropped URL can
/// arrive before the type is resolved.
enum DroppedImportKind: Equatable {
    /// A QTI package (.zip) — goes through the import picker.
    case qtiPackage
    /// A Common Cartridge (.imscc) — goes through the sectioned import picker.
    case commonCartridge
    /// Another Quiz Editor document — merges its questions into this one rather
    /// than replacing the open document, which is what File ▸ Open is for.
    case quizDocument

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "zip": self = .qtiPackage
        case "imscc": self = .commonCartridge
        case "quizeditor": self = .quizDocument
        default: return nil
        }
    }
}
