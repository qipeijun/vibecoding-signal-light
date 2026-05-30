import Darwin
import Dispatch
import Foundation

final class StateDirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?

    func start(directoryURL: URL, onChange: @escaping () -> Void) {
        stop()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        let nextSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: .main
        )
        nextSource.setEventHandler(handler: onChange)
        nextSource.setCancelHandler {
            close(descriptor)
        }
        nextSource.resume()
        source = nextSource
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }
}
