import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                FlameMark(size: 90)
                ProgressView()
            }
        }
    }
}

struct FlameMark: View {
    var size: CGFloat = 80
    var body: some View {
        Image("ox-logo")
            .resizable()
            .scaledToFit()
            .frame(height: size * 1.3)
            .shadow(color: Color.lime.opacity(0.55), radius: size * 0.3)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Повторить", action: retry)
                .buttonStyle(.glassProminent)
                .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Avatar: View {
    let url: URL?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        OxRemoteImage(url: url) {
            ZStack {
                Circle().fill(Color.lime.opacity(0.18))
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.lime)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct RemoteImage: View {
    let url: URL?
    var icon: String = "photo"

    var body: some View {
        OxRemoteImage(url: url, gated: true) {
            ZStack {
                Rectangle().fill(Color.white.opacity(0.06))
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(Color.lime.opacity(0.7))
            }
        }
    }
}

struct Chip: View {
    let text: String
    var selected = false

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.black : Color.primary)
            .background(selected ? Color.lime : Color.white.opacity(0.08), in: Capsule())
    }
}

struct NotRegisteredView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            FlameMark(size: 70)
            Text("Почти готово")
                .font(.title.bold())
            Text("Завершите регистрацию в Telegram-боте Oxion: выберите роль, город и цель. Потом вернитесь сюда.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            if let bot = model.meta?.botUsername, !bot.isEmpty,
               let url = URL(string: "https://t.me/\(bot.replacingOccurrences(of: "@", with: ""))") {
                Button {
                    openURL(url)
                } label: {
                    Label("Открыть бота", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
            }
            Button("Я зарегистрировался, проверить") {
                Task { await model.loadMe() }
            }
            .buttonStyle(.glass)
            .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
            Button("Выйти", role: .destructive) {
                Task { await model.logout() }
            }
            .padding(.top, 4)
        }
        .padding(24)
    }
}

// MARK: - Всплывающее сообщение в «стекле»

struct ToastModifier: ViewModifier {
    @Binding var text: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let t = text {
                Text(t)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: t) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { text = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: text)
    }
}

extension View {
    func toast(_ text: Binding<String?>) -> some View {
        modifier(ToastModifier(text: text))
    }
}
