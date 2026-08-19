import SwiftUI

struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore
    var isDropTargeted: Bool

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 130), spacing: 8)]

    var body: some View {
        if shelf.items.isEmpty {
            EmptyHint(
                symbol: isDropTargeted ? "tray.and.arrow.down.fill" : "tray",
                title: isDropTargeted ? "Отпускайте" : "Полка пуста",
                subtitle: "Поднесите файл к челке — панель раскроется сама"
            )
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Полка")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))

                Text("\(shelf.items.count)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.35))

                Spacer()

                Button(action: shelf.clear) {
                    Text("Очистить")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(shelf.items) { item in
                        ShelfCard(item: item, shelf: shelf)
                    }
                }
            }
        }
    }
}

struct ShelfCard: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfStore

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)

            Text(item.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(item.sizeText)
                .font(.system(size: 8))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.10 : 0.05))
        )
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    shelf.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(3)
            }
        }
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Открыть") { shelf.open(item) }
            Button("Показать в Finder") { shelf.reveal(item) }
            Divider()
            Button("Убрать с полки") { shelf.remove(item) }
        }
    }
}
