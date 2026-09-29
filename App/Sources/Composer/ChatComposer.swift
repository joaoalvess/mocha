import MochaClient
import PhotosUI
import SwiftUI

struct ChatComposer<ControlsPanel: View>: View {
    @Binding var draft: String
    @Binding var isExpanded: Bool
    var isFocused: FocusState<Bool>.Binding
    let attachments: ComposerAttachments
    var showsSlashMenu = true
    var isWorking = false
    let onSend: () -> Void
    var onStop: () -> Void = {}
    @ViewBuilder let controlsPanel: (_ maxHeight: CGFloat, _ close: @escaping () -> Void) -> ControlsPanel
    @State private var isAttachMenuOpen = false
    @State private var isSlashMenuOpen = false
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var pasteboardHasImages = false
    @State private var dictation = DictationController()
    @State private var composerTop: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        composer
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $pickedPhotos,
                maxSelectionCount: max(1, attachments.remainingSlots),
                selectionBehavior: .ordered,
                matching: .images
            )
            .fullScreenCover(isPresented: $isCameraPresented) {
                CameraCapture(
                    onCapture: { image in
                        isCameraPresented = false
                        attach([ComposerImageSources.loader(for: image)])
                    },
                    onCancel: { isCameraPresented = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: pickedPhotos) { _, items in
                guard !items.isEmpty else { return }
                pickedPhotos = []
                attach(items.map(ComposerImageSources.loader(for:)))
            }
            .onChange(of: isExpanded) { _, expanded in
                if !expanded {
                    closeMenus()
                    dictation.stop()
                }
            }
            .onChange(of: draft) {
                closeMenus()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { dictation.stop() }
            }
            .task { await dictation.resolveAvailability() }
            .onDisappear { dictation.cancel() }
    }

    @ViewBuilder
    private var composer: some View {
        if isExpanded {
            ExpandedComposer(
                canSend: canSend,
                sendMode: sendMode,
                buttons: expandedButtons,
                activeButtons: activeButtons,
                onAttach: toggleAttachMenu,
                onSlashMenu: toggleSlashMenu,
                onMicrophone: toggleDictation,
                onSend: send,
                onStop: onStop
            ) {
                VStack(alignment: .leading, spacing: AttachmentLayout.stripBottomSpacing) {
                    if !attachments.isEmpty {
                        AttachmentStrip(attachments: attachments.items) { attachments.remove($0) }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ComposerTextField(text: $draft)
                            .focused(isFocused)
                        DictationLineView(line: dictation.line)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { composerTop = $0 }
            .overlay(alignment: .topLeading) { attachMenu }
            .overlay(alignment: .topLeading) { slashMenu }
            .animation(.smooth(duration: 0.2), value: isAttachMenuOpen)
            .animation(.smooth(duration: 0.2), value: isSlashMenuOpen)
            .onAppear {
                isFocused.wrappedValue = true
                openMenusForDebugLaunch()
            }
        } else {
            CollapsedComposer(draft: collapsedDraft, sendMode: sendMode, onExpand: { isExpanded = true }, onSend: send, onStop: onStop)
        }
    }

    @ViewBuilder
    private var attachMenu: some View {
        if isAttachMenuOpen {
            AttachMenu(
                showsCamera: ComposerImageSources.isCameraAvailable,
                isFull: attachments.isFull,
                canPaste: pasteboardHasImages,
                onPhotos: {
                    isAttachMenuOpen = false
                    isPhotoPickerPresented = true
                },
                onCamera: {
                    isAttachMenuOpen = false
                    isCameraPresented = true
                },
                onPaste: {
                    isAttachMenuOpen = false
                    attach(ComposerImageSources.pastedImages(limit: attachments.remainingSlots).map(ComposerImageSources.loader(for:)))
                }
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: 0, alignment: .bottomLeading)
            .offset(y: -AttachmentLayout.menuGap)
            .transition(.scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var slashMenu: some View {
        if isSlashMenuOpen {
            controlsPanel(composerTop - AttachmentLayout.menuGap - ControlsPanelLayout.topReserve) { isSlashMenuOpen = false }
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: 0, alignment: .bottomLeading)
            .offset(y: -AttachmentLayout.menuGap)
            .transition(.scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity))
        }
    }

    private var canSend: Bool {
        !attachments.isProcessing
            && (!ComposerDraft.trimmed(draft).isEmpty || !dictation.partial.isEmpty || !attachments.isEmpty)
    }

    private var sendMode: ComposerSendMode {
        let hasContent = !ComposerDraft.trimmed(draft).isEmpty || !dictation.partial.isEmpty || !attachments.isEmpty
        return ComposerSendMode.mode(hasContent: hasContent, isWorking: isWorking)
    }

    private var expandedButtons: ComposerButtons {
        var buttons: ComposerButtons = [.attach]
        if showsSlashMenu { buttons.insert(.slashMenu) }
        if dictation.phase.showsMicrophone { buttons.insert(.microphone) }
        return buttons
    }

    private var activeButtons: ComposerButtons {
        var active: ComposerButtons = []
        if isSlashMenuOpen { active.insert(.slashMenu) }
        if dictation.phase.isListening { active.insert(.microphone) }
        return active
    }

    private var collapsedDraft: String {
        guard ComposerDraft.trimmed(draft).isEmpty, !attachments.isEmpty else { return draft }
        return PromptImages.attachmentLabel(imageCount: attachments.items.count)
    }

    private func toggleAttachMenu() {
        if !isAttachMenuOpen {
            pasteboardHasImages = ComposerImageSources.pasteboardHasImages
        }
        isSlashMenuOpen = false
        isAttachMenuOpen.toggle()
    }

    private func toggleSlashMenu() {
        guard showsSlashMenu else { return }
        isAttachMenuOpen = false
        isSlashMenuOpen.toggle()
    }

    private func closeMenus() {
        isAttachMenuOpen = false
        isSlashMenuOpen = false
    }

    private func toggleDictation() {
        closeMenus()
        dictation.toggle { [draft = $draft] text in
            draft.wrappedValue = DictationText.appending(text, to: draft.wrappedValue)
        }
    }

    private func send() {
        dictation.commitPartialAndCancel()
        onSend()
    }

    private func attach(_ loaders: [ComposerImageLoader]) {
        guard !loaders.isEmpty else { return }
        attachments.add(loaders)
        isExpanded = true
    }

    private func openMenusForDebugLaunch() {
        #if DEBUG
        let options = ChatDebugOptions.current()
        if options.opensAttachMenu, ChatDebugLaunch.consume(ChatDebugOptions.attachMenuKey) {
            toggleAttachMenu()
        }
        if options.opensSlashMenu, ChatDebugLaunch.consume(ChatDebugOptions.slashMenuKey) {
            toggleSlashMenu()
        }
        #endif
    }
}

struct ReadOnlyComposerPill: View {
    var text = "Sessão encerrada · só leitura"
    var body: some View {
        Text(text)
            .font(Typography.composer)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.composerHeight)
            .mochaGlass(.composer, in: Capsule())
    }
}

enum ComposerDraft {
    static func trimmed(_ draft: String) -> String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ControlsPanelLayout {
    static let topReserve = Metrics.headerTopInset + Metrics.headerHeight + 72
}
