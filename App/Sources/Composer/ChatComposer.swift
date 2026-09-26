import MochaClient
import PhotosUI
import SwiftUI

struct ChatComposer: View {
    @Binding var draft: String
    @Binding var isExpanded: Bool
    var isFocused: FocusState<Bool>.Binding
    let attachments: ComposerAttachments
    let onSend: () -> Void
    let onSlashAction: (SlashMenuAction) -> Void
    @State private var isAttachMenuOpen = false
    @State private var isSlashMenuOpen = false
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var pasteboardHasImages = false

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
                if !expanded { closeMenus() }
            }
            .onChange(of: draft) {
                closeMenus()
            }
    }

    @ViewBuilder
    private var composer: some View {
        if isExpanded {
            ExpandedComposer(
                canSend: canSend,
                buttons: [.attach, .slashMenu],
                activeButtons: isSlashMenuOpen ? .slashMenu : [],
                onAttach: toggleAttachMenu,
                onSlashMenu: toggleSlashMenu,
                onSend: onSend
            ) {
                VStack(alignment: .leading, spacing: AttachmentLayout.stripBottomSpacing) {
                    if !attachments.isEmpty {
                        AttachmentStrip(attachments: attachments.items) { attachments.remove($0) }
                    }
                    ComposerTextField(text: $draft)
                        .focused(isFocused)
                }
            }
            .overlay(alignment: .topLeading) { attachMenu }
            .overlay(alignment: .topLeading) { slashMenu }
            .animation(.smooth(duration: 0.2), value: isAttachMenuOpen)
            .animation(.smooth(duration: 0.2), value: isSlashMenuOpen)
            .onAppear {
                isFocused.wrappedValue = true
                openMenusForDebugLaunch()
            }
        } else {
            CollapsedComposer(draft: collapsedDraft, onExpand: { isExpanded = true }, onSend: onSend)
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
            SlashMenu { action in
                isSlashMenuOpen = false
                onSlashAction(action)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: 0, alignment: .bottomLeading)
            .offset(y: -AttachmentLayout.menuGap)
            .transition(.scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity))
        }
    }

    private var canSend: Bool {
        !attachments.isProcessing && (!ComposerDraft.trimmed(draft).isEmpty || !attachments.isEmpty)
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
        isAttachMenuOpen = false
        isSlashMenuOpen.toggle()
    }

    private func closeMenus() {
        isAttachMenuOpen = false
        isSlashMenuOpen = false
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
    var body: some View {
        Text("Sessão encerrada · só leitura")
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
