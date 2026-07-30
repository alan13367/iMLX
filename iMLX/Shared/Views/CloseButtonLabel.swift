import SwiftUI

struct CloseButtonLabel: View {
    var foregroundStyle: Color = .primary

    var body: some View {
        Image(systemName: "xmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(foregroundStyle)
            .frame(width: 44, height: 44)
    }
}
