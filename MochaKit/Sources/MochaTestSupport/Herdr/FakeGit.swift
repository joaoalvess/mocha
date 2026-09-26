import Foundation
import MochaDaemonCore
import Synchronization

public final class FakeGitInspector: GitInspecting {
    private struct State {
        var branches: [String: String]
        var dirtyDirectories: Set<String>
        var dirtyChecks: [String] = []
        var invalidations: [String] = []
    }

    private let state: Mutex<State>

    public init(branches: [String: String] = [:], dirtyDirectories: Set<String> = []) {
        state = Mutex(State(branches: branches, dirtyDirectories: dirtyDirectories))
    }

    public func branch(at directory: String) async -> String? {
        state.withLock { $0.branches[directory] }
    }

    public func isDirty(at directory: String) async -> Bool {
        state.withLock { state in
            state.dirtyChecks.append(directory)
            return state.dirtyDirectories.contains(directory)
        }
    }

    public func invalidateDirty(at directory: String) async {
        state.withLock { $0.invalidations.append(directory) }
    }

    public func setBranch(_ branch: String?, at directory: String) {
        state.withLock { $0.branches[directory] = branch }
    }

    public func setDirty(_ dirty: Bool, at directory: String) {
        state.withLock { state in
            if dirty {
                state.dirtyDirectories.insert(directory)
            } else {
                state.dirtyDirectories.remove(directory)
            }
        }
    }

    public var dirtyChecks: [String] {
        state.withLock { $0.dirtyChecks }
    }

    public var invalidations: [String] {
        state.withLock { $0.invalidations }
    }
}

public final class FakeGitCommandRunner: GitCommandRunning {
    private struct State {
        var result: GitCommandResult
        var calls: [[String]] = []
    }

    private let state: Mutex<State>

    public init(result: GitCommandResult = GitCommandResult(exitCode: 0, output: Data())) {
        state = Mutex(State(result: result))
    }

    public func run(arguments: [String]) async throws -> GitCommandResult {
        state.withLock { state in
            state.calls.append(arguments)
            return state.result
        }
    }

    public func setResult(_ result: GitCommandResult) {
        state.withLock { $0.result = result }
    }

    public var calls: [[String]] {
        state.withLock { $0.calls }
    }
}
