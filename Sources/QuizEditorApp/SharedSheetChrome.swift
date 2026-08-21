import SwiftUI

/// The title block at the top of a sheet. Pass a `systemImage` for sheets whose
/// subject has an established icon; omit it for plain ones. `subtitle` is for
/// sheets that need a line of explanation under the title.
@MainActor
@ViewBuilder
func sheetHeader(_ title: String, systemImage: String? = nil, subtitle: String? = nil) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.title2.bold())
            } else {
                Text(title)
                    .font(.title2.bold())
            }
            if let subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Spacer()
    }
    .padding(20)
}

/// The confirm/cancel row at the bottom of a sheet.
///
/// `leading` fills the space opposite the buttons, for sheets that explain what
/// the confirm button is about to do.
@MainActor
@ViewBuilder
func sheetFooter<Leading: View>(
    confirmTitle: String = "Save",
    isEnabled: Bool = true,
    @ViewBuilder leading: () -> Leading = { EmptyView() },
    onConfirm: @escaping () -> Void,
    onCancel: @escaping () -> Void
) -> some View {
    HStack {
        leading()
        Spacer()
        Button("Cancel", action: onCancel)
            .keyboardShortcut(.cancelAction)
        Button(confirmTitle, action: onConfirm)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!isEnabled)
    }
    .padding(20)
}
