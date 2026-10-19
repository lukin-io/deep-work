import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            NavigationTabs(selection: $model.selectedTab)
                .frame(width: 300, height: 30).padding(.top, 12).padding(.bottom, 8)
            if let message = model.lifecycleFailureMessage {
                Text(message)
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.top, 8)
                    .accessibilityIdentifier("dw-lifecycle-error")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        switch model.selectedTab {
                        case .focus: FocusView(model: model)
                        case .journal:
                            JournalView(model: model, revealActivity: { proxy.scrollTo(JournalScrollTarget.activity) })
                        case .settings: SettingsView(model: model)
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.accentColor)
        .disabled(model.isTerminating)
        .onChange(of: model.lifecycleFailureMessage) { _, message in
            guard let message else { return }
            model.announce(message, priority: .high)
        }
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

struct AvailabilityNote: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
