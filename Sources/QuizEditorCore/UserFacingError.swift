import Foundation

/// An error whose `description` is the sentence the user should read.
///
/// Every error in this module already wrote a plain-language `description`, but
/// the app shows errors through `localizedDescription`, and Foundation only
/// consults `description` when the type conforms to `LocalizedError`. Without
/// this the import alert said "The operation couldn't be completed.
/// (QuizEditorCore.QTIImporter.ImportError error 2.)" — an enum ordinal — while
/// the sentence we wrote sat unused.
public protocol UserFacingError: LocalizedError, CustomStringConvertible {}

public extension UserFacingError {
    var errorDescription: String? { description }
}
