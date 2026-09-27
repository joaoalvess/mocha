import Foundation
import Observation
import Speech

@MainActor
@Observable
final class DictationController {
    typealias FinalHandler = @MainActor (String) -> Void

    private static let progressInterval = Duration.milliseconds(200)

    private(set) var phase: DictationPhase = .checking
    private(set) var partial = ""

    @ObservationIgnored private var locale: Locale?
    @ObservationIgnored private var pipeline: DictationPipeline?
    @ObservationIgnored private var results: Task<Void, Never>?
    @ObservationIgnored private var onFinal: FinalHandler?
    @ObservationIgnored private var session = 0

    var line: DictationLine? {
        DictationLine(phase: phase, partial: partial)
    }

    func resolveAvailability() async {
        guard phase == .checking else { return }
        locale = await DictationSupport.transcriptionLocale()
        apply(.availabilityResolved(isSupported: locale != nil))
    }

    func toggle(onFinal: @escaping FinalHandler) {
        switch phase.toggle {
        case .start: start(onFinal: onFinal)
        case .stop: finishListening()
        case .ignore: break
        }
    }

    func stop() {
        switch phase {
        case .listening: finishListening()
        case .preparing, .downloading, .failed: cancel()
        case .checking, .unavailable, .ready, .finishing: break
        }
    }

    func commitPartialAndCancel() {
        if !partial.isEmpty {
            onFinal?(partial)
        }
        cancel()
    }

    func cancel() {
        guard phase.isSessionActive else { return }
        let running = pipeline
        endSession()
        apply(.cancelled)
        if let running {
            Task { await running.cancel() }
        }
    }

    private func start(onFinal: @escaping FinalHandler) {
        guard let locale else { return }
        session += 1
        let token = session
        self.onFinal = onFinal
        partial = ""
        apply(.startRequested)
        Task { await prepareAndListen(locale: locale, token: token) }
    }

    private func prepareAndListen(locale: Locale, token: Int) async {
        guard await DictationSupport.requestMicrophoneAccess() else {
            fail(.microphoneDenied, token: token)
            return
        }
        guard isCurrent(token) else { return }
        let transcriber = DictationSupport.makeTranscriber(locale: locale)
        let status = await AssetInventory.status(forModules: [transcriber])
        guard isCurrent(token) else { return }
        if status == .unsupported {
            markUnavailable()
            return
        }
        do {
            try await installModel(for: transcriber, token: token)
        } catch {
            fail(.modelDownloadFailed, token: token)
            return
        }
        guard isCurrent(token) else { return }
        let started: DictationPipeline
        do throws(DictationFailure) {
            started = try await DictationPipeline.start(transcriber: transcriber)
        } catch {
            fail(error, token: token)
            return
        }
        guard isCurrent(token) else {
            await started.cancel()
            return
        }
        pipeline = started
        listen(to: transcriber, token: token)
        apply(.listeningStarted)
    }

    private func installModel(for transcriber: SpeechTranscriber, token: Int) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        guard isCurrent(token) else { return }
        let progress = Task { [weak self] in
            while !Task.isCancelled {
                self?.downloadProgressed(request.progress.fractionCompleted, token: token)
                try? await Task.sleep(for: Self.progressInterval)
            }
        }
        defer { progress.cancel() }
        try await request.downloadAndInstall()
        guard isCurrent(token) else { return }
        apply(.downloadFinished)
    }

    private func listen(to transcriber: SpeechTranscriber, token: Int) {
        results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.receive(result, token: token)
                }
                self?.resultsEnded(token: token, failure: nil)
            } catch {
                self?.resultsEnded(token: token, failure: .recognitionFailed)
            }
        }
    }

    private func receive(_ result: SpeechTranscriber.Result, token: Int) {
        guard isCurrent(token) else { return }
        let text = String(result.text.characters)
        if result.isFinal {
            partial = ""
            onFinal?(text)
        } else {
            partial = DictationText.partial(text)
        }
    }

    private func finishListening() {
        guard let running = pipeline else { return }
        pipeline = nil
        apply(.stopRequested)
        Task { await running.finish() }
    }

    private func resultsEnded(token: Int, failure: DictationFailure?) {
        guard isCurrent(token) else { return }
        let running = pipeline
        endSession()
        apply(failure.map(DictationEvent.failed) ?? .finished)
        if let running {
            Task { await running.cancel() }
        }
    }

    private func downloadProgressed(_ fraction: Double, token: Int) {
        guard isCurrent(token) else { return }
        apply(.downloadProgressed(fraction: fraction))
    }

    private func fail(_ failure: DictationFailure, token: Int) {
        guard isCurrent(token) else { return }
        endSession()
        apply(.failed(failure))
    }

    private func markUnavailable() {
        endSession()
        apply(.availabilityResolved(isSupported: false))
    }

    private func endSession() {
        session += 1
        pipeline = nil
        results?.cancel()
        results = nil
        onFinal = nil
        partial = ""
    }

    private func isCurrent(_ token: Int) -> Bool {
        token == session
    }

    private func apply(_ event: DictationEvent) {
        let next = phase.applying(event)
        if next != phase {
            phase = next
        }
    }
}
