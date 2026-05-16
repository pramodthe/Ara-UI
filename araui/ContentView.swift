//
//  ContentView.swift
//  nova
import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject private var vm: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            chatList
            Divider()
            inputBar
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(Color(nsColor: .textBackgroundColor))
        // Attach the window accessor invisibly so it doesn't affect layout
        .background(WindowAccessor().frame(width: 0, height: 0))
        .overlay(alignment: .top) {
            SpeechCaptureOverlay(isVisible: vm.isHotkeyCaptureActive || vm.isListening,
                                 partialText: vm.partialTranscript,
                                 app: vm.recognizedApp)
        }
    }

    private var header: some View {
        HStack {
            Label("AraUI", systemImage: "sparkles")
                .font(.title3.weight(.semibold))
            Spacer()
            #if os(macOS)
            if vm.inputDevices.isEmpty == false {
                Picker("Input", selection: Binding(
                    get: { vm.selectedInputDeviceUID ?? "" },
                    set: { newUID in
                        vm.selectedInputDeviceUID = newUID.isEmpty ? nil : newUID
                        vm.applySelectedInputDevice()
                    }
                )) {
                    ForEach(vm.inputDevices, id: \.uid) { dev in
                        Text(dev.name).tag(dev.uid)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .help("Choose input microphone")
            }
            #endif
            if let app = vm.recognizedApp {
                HStack(spacing: 6) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: "app")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    Text(app.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 8)
                .help("Frontmost app recognized by AraUI")
            }
            Toggle("Auto-capture", isOn: Binding(
                get: { vm.autoCaptureEnabled },
                set: { vm.setAutoCapture($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .help("Continuously capture text from the frontmost window and attach as context (no auto-send)")
            
            Button(action: { vm.toggleMute() }) {
                Image(systemName: vm.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(vm.isMuted ? .secondary : .primary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(vm.isMuted ? "Unmute voice responses" : "Mute voice responses")
            
            ImageGenButton()
            
            if vm.isStreaming { ProgressView().controlSize(.small) }
            if vm.isSpeaking {
                Button(action: { vm.stopSpeaking() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11))
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.8)))
                }
                .buttonStyle(.plain)
                .help("Stop speaking")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(vm.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                    if vm.isStreaming { TypingIndicator() }
                    if let err = vm.errorMessage {
                        ErrorBanner(text: err)
                    }
                }
                .padding(16)
            }
            .onChange(of: vm.messages.count) { _ in
                if let last = vm.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let ctx = vm.pendingContext {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text("Context attached (\(ctx.count) chars)\(vm.recognizedApp != nil ? " from \(vm.recognizedApp!.name)" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Button(action: { vm.clearPendingContext() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Remove attached selection context")
                }
                .padding(.horizontal, 4)
            }
            HStack(alignment: .center, spacing: 8) {
                ChatInputTextView(text: $vm.input, isEnabled: !vm.isStreaming) {
                    Task { await vm.send() }
                }
                .frame(minHeight: 24, maxHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.25))
                )
                // Do not use SwiftUI .disabled on NSViewRepresentable text view; manage editability internally
                .overlay(alignment: .leading) {
                    if let partial = vm.partialTranscript, vm.isListening && vm.input.isEmpty {
                        Text(partial)
                            .foregroundStyle(.secondary)
                            .font(.body)
                            .lineLimit(2)
                            .padding(.leading, 10)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }

                // Mic button
                Button(action: { vm.toggleMic() }) {
                    Image(systemName: vm.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(vm.isListening ? Color.red.opacity(0.9) : Color.accentColor))
                }
                .buttonStyle(.plain)
                .help(vm.isListening ? "Stop voice input" : "Start voice input")

                Button(action: { Task { await vm.send() } }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(vm.isStreaming || vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.5) : Color.accentColor))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isStreaming)
            }
        }
        .padding(10)
        .padding(.horizontal, 8)
    }
}

private struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .model {
                avatar
                bubble
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                bubble
                avatar
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var avatar: some View {
        Circle()
            .fill(message.role == .user ? Color.accentColor : Color.purple.opacity(0.8))
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                    .foregroundStyle(.white)
                    .font(.system(size: 13, weight: .semibold))
            )
    }

    private var bubble: some View {
        MarkdownBlockText(markdown: message.text)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(message.role == .user ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12))
            )
            .frame(maxWidth: 560, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct TypingIndicator: View {
    @State private var dotCount: Int = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    var body: some View {
        Text("working on it" + String(repeating: ".", count: dotCount))
            .foregroundStyle(.secondary)
            .font(.body)
            .onReceive(timer) { _ in
                dotCount = (dotCount + 1) % 4
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

private struct ErrorBanner: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(text)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
    }
}


private struct SpeechCaptureOverlay: View {
    let isVisible: Bool
    let partialText: String?
    let app: RecognizedApp?

    @State private var display: Bool = false

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                overlayContent
            }
            .padding(18)
            .frame(maxWidth: min(proxy.size.width - 32, 520))
            .background(.ultraThinMaterial.opacity(0.85))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 12)
            .offset(y: display ? 34 : -140)
            .opacity(display ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
        .frame(height: 0)
        .onChange(of: isVisible) { visible in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0.2)) {
                display = visible
            }
        }
        .onAppear {
            display = false
            if isVisible {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0.2)) {
                    display = true
                }
            }
        }
    }

    private var overlayContent: some View {
        HStack(spacing: 10) {
            if let icon = app?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(app?.name ?? "Listening…")
                    .font(.headline)
                    .foregroundStyle(.white)
                if let partial = partialText, partial.isEmpty == false {
                    Text(partial)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                } else {
                    Text("Speak now, AraUI is capturing context")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            ListeningPill()
        }
    }
}

private struct ListeningPill: View {
    @State private var showPulse: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red.opacity(0.85))
                .frame(width: 10, height: 10)
                .scaleEffect(showPulse ? 1.3 : 0.9)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: showPulse)
            Text("Listening")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.12))
        )
        .onAppear { showPulse = true }
    }
}

private struct ImageGenButton: View {
    @State private var showPopover = false
    
    var body: some View {
        Button(action: { showPopover.toggle() }) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 14, weight: .regular))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help("Generate image from screen clip (Option+C to capture)")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ImageGenerationView()
        }
    }
}

#Preview { ContentView() }
