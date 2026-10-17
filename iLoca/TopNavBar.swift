import SwiftUI

/// Pages reachable from the top nav, in scroll order.
enum AppPage: String, CaseIterable, Identifiable {
    case home = "Home", map = "Map", guide = "Guide", info = "Info"
    var id: String { rawValue }
}

/// Shared top navigation used on every page: logo dot + wordmark, the active
/// page highlighted in mint, everything else muted grey.
struct TopNavBar: View {
    let activePage: AppPage
    var onNavTap: ((AppPage) -> Void)? = nil

    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.defaultMode.rawValue

    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppColor.tealAccent)
                    .frame(width: 9, height: 9)
                Text("iLoca")
                    .font(AppFont.nav(19, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
            }

            Spacer()

            HStack(spacing: 26) {
                ForEach(AppPage.allCases) { page in
                    Text(page.rawValue)
                        .font(AppFont.nav(14, weight: page == activePage ? .semibold : .regular))
                        .foregroundStyle(page == activePage ? AppColor.mintLight : AppColor.mutedGrey)
                        .contentShape(Rectangle())
                        .onTapGesture { onNavTap?(page) }
                }
                appearanceMenu
            }
        }
    }

    private var appearanceMenu: some View {
        let current = AppearanceMode(rawValue: appearance) ?? .defaultMode
        return Menu {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: current.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.mutedGrey)
                .frame(width: 28, height: 28)
                .background(Circle().fill(AppColor.textPrimary.opacity(0.06)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Appearance: \(current.label)")
    }
}

// MARK: - "Report an issue" entry point, available anywhere in the view tree

extension EnvironmentValues {
    @Entry var reportIssue: (IssueContext) -> Void = { _ in }
}
