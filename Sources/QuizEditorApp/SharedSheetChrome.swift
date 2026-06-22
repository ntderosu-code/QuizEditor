import SwiftUI

@MainActor
@ViewBuilder
func sheetHeader(_ title: String, systemImage: String) -> some View {
    HStack {
        Label(title, systemImage: systemImage)
            .font(.title2.bold())
        Spacer()
    }
    .padding(20)
}

@MainActor
@ViewBuilder
func sheetFooter(canSave: Bool, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
    HStack {
        Spacer()
        Button("Cancel", action: onCancel)
            .keyboardShortcut(.cancelAction)
        Button("Save", action: onSave)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
    }
    .padding(20)
}
