import MochaClient
import MochaProtocol
import PhotosUI
import SwiftUI

struct ChatComposer<ControlsPanel: View>: View {
    @Binding var draft: String
    @Binding var isExpanded: Bool
    var isFocused: FocusState<Bool>.Binding
    let attachments: ComposerAttachments
    var showsSlashMenu = true
    var isWorking = false
    var effort: EffortLevel?
    var onModelPicker: (() -> Void)?
    let onSend: () -> Void
    var onStop: () -> Void = {}
    @ViewBuilder let controlsPanel: (_ maxHeight: CGFloat, _ close: @escaping () -> Void) -> ControlsPanel
    @State private var isAttachMenuOpen = false
    @State private var isSlashMenuOpen = false
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var dictation = DictationController()
    @State private var composerFrame: CGRect = .zero
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        composer
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { composerFrame = $0 }
            .background { menuLayer }
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
                effort: effort,
                onAttach: toggleAttachMenu,
                onSlashMenu: toggleSlashMenu,
                onMicrophone: primaryDictationAction,
                onSend: send,
                onStop: onStop,
                onModelPicker: openModelPicker
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
            .onAppear {
                isFocused.wrappedValue = true
                openMenusForDebugLaunch()
            }
        } else {
            CollapsedComposer(
                draft: collapsedDraft,
                sendMode: sendMode,
                buttons: [.attach],
                onAttach: toggleAttachMenu,
                onExpand: { isExpanded = true },
                onSend: send,
                onStop: onStop,
                onMicrophone: expandAndDictate
            )
        }
    }

    private var attachMenu: some View {
        AttachMenu(
            showsCamera: ComposerImageSources.isCameraAvailable,
            isFull: attachments.isFull,
            canDictate: dictation.phase.showsMicrophone,
            onPhotos: {
                isAttachMenuOpen = false
                isPhotoPickerPresented = true
            },
            onCamera: {
                isAttachMenuOpen = false
                isCameraPresented = true
            },
            onAudio: {
                isAttachMenuOpen = false
                expandAndDictate()
            }
        )
    }

    private var menuLayer: some View {
        FloatingMenuLayer(
            content: ComposerFloatingMenus(
                isAttachMenuOpen: isAttachMenuOpen,
                isControlsPanelOpen: isSlashMenuOpen,
                anchor: composerFrame,
                onDismiss: closeMenus,
                attachMenu: { attachMenu },
                controlsPanel: { maxHeight in controlsPanel(maxHeight) { isSlashMenuOpen = false } }
            )
        )
    }

    private var canSend: Bool {
        !attachments.isProcessing
            && (!ComposerDraft.trimmed(draft).isEmpty || !dictation.partial.isEmpty || !attachments.isEmpty)
    }

    private var sendMode: ComposerSendMode {
        let hasContent = !ComposerDraft.trimmed(draft).isEmpty || !dictation.partial.isEmpty || !attachments.isEmpty
        return ComposerSendMode.mode(
            hasContent: hasContent,
            isWorking: isWorking,
            isDictating: isDictating,
            canDictate: dictation.phase.showsMicrophone
        )
    }

    private var isDictating: Bool {
        switch dictation.phase {
        case .preparing, .downloading, .listening: true
        case .checking, .unavailable, .ready, .finishing, .failed: false
        }
    }

    private var expandedButtons: ComposerButtons {
        var buttons: ComposerButtons = [.attach]
        if onModelPicker != nil { buttons.insert(.modelPicker) }
        if showsSlashMenu { buttons.insert(.slashMenu) }
        return buttons
    }

    private var activeButtons: ComposerButtons {
        isSlashMenuOpen ? [.slashMenu] : []
    }

    private var collapsedDraft: String {
        guard ComposerDraft.trimmed(draft).isEmpty, !attachments.isEmpty else { return draft }
        return PromptImages.attachmentLabel(imageCount: attachments.items.count)
    }

    private func toggleAttachMenu() {
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

    private func expandAndDictate() {
        isExpanded = true
        toggleDictation()
    }

    private func openModelPicker() {
        closeMenus()
        onModelPicker?()
    }

    private func primaryDictationAction() {
        if isDictating {
            dictation.stop()
        } else {
            toggleDictation()
        }
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
    static let attachAnchor = UnitPoint(x: 26 / AttachmentLayout.menuWidth, y: 1)
    static let buttonAnchor = UnitPoint(x: 66 / AttachmentLayout.menuWidth, y: 1)
    static let topReserve = Metrics.headerTopInset + Metrics.headerHeight + 55
    static let bottomMargin: CGFloat = 8
}

struct ComposerFloatingMenus<Attach: View, Panel: View>: View {
    let isAttachMenuOpen: Bool
    let isControlsPanelOpen: Bool
    let anchor: CGRect
    let onDismiss: () -> Void
    @ViewBuilder let attachMenu: () -> Attach
    @ViewBuilder let controlsPanel: (_ maxHeight: CGFloat) -> Panel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isAttachMenuOpen || isControlsPanelOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                    .ignoresSafeArea()
                    .floatingMenuHitRegion()
                    .accessibilityHidden(true)
            }
            FloatingComposerMenu(isPresented: isAttachMenuOpen, anchor: anchor, scaleAnchor: ControlsPanelLayout.attachAnchor) { _ in
                attachMenu()
            }
            FloatingComposerMenu(isPresented: isControlsPanelOpen, anchor: anchor, scaleAnchor: ControlsPanelLayout.buttonAnchor) { maxHeight in
                controlsPanel(maxHeight)
            }
        }
    }
}

struct FloatingComposerMenu<Menu: View>: View {
    let isPresented: Bool
    let anchor: CGRect
    let scaleAnchor: UnitPoint
    @ViewBuilder let menu: (_ maxHeight: CGFloat) -> Menu
    @State private var menuHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let maxBottom = min(anchor.maxY, proxy.size.height - proxy.safeAreaInsets.bottom - ControlsPanelLayout.bottomMargin)
            let minTop = ControlsPanelLayout.topReserve
            ZStack(alignment: .topLeading) {
                Color.clear
                    .allowsHitTesting(false)
                if isPresented {
                    menu(FloatingMenuPlacement.maxHeight(minTop: minTop, maxBottom: maxBottom))
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { menuHeight = $0 }
                        .opacity(menuHeight > 0 ? 1 : 0)
                        .offset(
                            x: anchor.minX,
                            y: FloatingMenuPlacement.top(
                                height: menuHeight,
                                preferredBottom: anchor.minY - AttachmentLayout.menuGap,
                                minTop: minTop,
                                maxBottom: maxBottom
                            )
                        )
                        .transition(.scale(scale: 0.3, anchor: scaleAnchor).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.2), value: isPresented)
    }
}
