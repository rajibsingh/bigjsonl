import SwiftUI

struct TabBarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tabs: [TabItem]
    let selectedID: UUID
    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onNew: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        tabChip(tab)
                        Divider()
                            .frame(height: 16)
                    }
                }
                .padding(.horizontal, 4)
            }

            Divider()
                .frame(height: 16)

            Button {
                onNew()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("New Tab")
        }
        .frame(height: 32)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func tabChip(_ tab: TabItem) -> some View {
        let isSelected = tab.id == selectedID

        return Button {
            onSelect(tab.id)
        } label: {
            HStack(spacing: 4) {
                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 160, alignment: .leading)

                Button {
                    onClose(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isSelected ? .secondary : .tertiary)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help("Close Tab")
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selectedTabFill)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 4)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.accentColor.opacity(colorScheme == .dark ? 0.55 : 0.35), lineWidth: 1)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 4)
                }
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .padding(.horizontal, 12)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var selectedTabFill: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.24)
            : Color.accentColor.opacity(0.13)
    }
}
