import AVFAudio
import Speech
import Synchronization

final class DictationPipeline: Sendable {
    private static let tapBufferSize: AVAudioFrameCount = 4096

    private let engine: AVAudioEngine
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let isCaptureStopped = Atomic(false)

    private init(engine: AVAudioEngine, analyzer: SpeechAnalyzer, input: AsyncStream<AnalyzerInput>.Continuation) {
        self.engine = engine
        self.analyzer = analyzer
        self.input = input
    }

    static func start(transcriber: SpeechTranscriber) async throws(DictationFailure) -> DictationPipeline {
        let modules: [any SpeechModule] = [transcriber]
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw DictationFailure.recognitionFailed
        }
        do {
            try DictationAudioSession.activate()
        } catch {
            DictationAudioSession.deactivate()
            throw DictationFailure.audioUnavailable
        }
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let pipeline = DictationPipeline(
            engine: AVAudioEngine(),
            analyzer: SpeechAnalyzer(modules: modules),
            input: input
        )
        do {
            let preparedFormat = AVAudioFormat(
                commonFormat: analyzerFormat.commonFormat,
                sampleRate: analyzerFormat.sampleRate,
                channels: analyzerFormat.channelCount,
                interleaved: analyzerFormat.isInterleaved
            )
            try await pipeline.analyzer.prepareToAnalyze(in: preparedFormat)
            try await pipeline.analyzer.start(inputSequence: stream)
        } catch {
            await pipeline.cancel()
            throw DictationFailure.recognitionFailed
        }
        do {
            try pipeline.startCapture(convertingTo: analyzerFormat)
        } catch {
            await pipeline.cancel()
            throw DictationFailure.audioUnavailable
        }
        return pipeline
    }

    func finish() async {
        stopCapture()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
    }

    func cancel() async {
        stopCapture()
        await analyzer.cancelAndFinishNow()
    }

    private func startCapture(convertingTo analyzerFormat: AVAudioFormat) throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard
            inputFormat.sampleRate > 0,
            inputFormat.channelCount > 0,
            let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
        else { throw DictationFailure.audioUnavailable }
        let input = self.input
        inputNode.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: inputFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, using: converter, to: analyzerFormat) else { return }
            input.yield(AnalyzerInput(buffer: converted))
        }
        engine.prepare()
        try engine.start()
    }

    private func stopCapture() {
        guard !isCaptureStopped.exchange(true, ordering: .acquiringAndReleasing) else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        input.finish()
        DictationAudioSession.deactivate()
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard capacity > 0, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        var isConsumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard !isConsumed else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            isConsumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, conversionError == nil, output.frameLength > 0 else { return nil }
        return output
    }
}

enum DictationAudioSession {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum DictationSupport {
    static let requestedLocale = Locale(identifier: "pt-BR")

    static func transcriptionLocale() async -> Locale? {
        guard
            SpeechTranscriber.isAvailable,
            let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)
        else { return nil }
        let status = await AssetInventory.status(forModules: [makeTranscriber(locale: locale)])
        return status == .unsupported ? nil : locale
    }

    static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    }

    static func requestMicrophoneAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .denied: false
        case .undetermined: await AVAudioApplication.requestRecordPermission()
        @unknown default: false
        }
    }
}
