import Foundation
import StoryBatchCore

enum QueueMove { case up, down, next }

extension QueuedWork {
    /// Split only execution boundaries; shared accounting still describes one user request.
    func fragmented() throws -> [QueuedWork] {
        guard round == nil, let prepared else { return [self] }
        let round = QueuedRound(id: prepared.logicalRunID ?? UUID().uuidString,
                                count: prepared.compiled.parameters.count, counted: false)
        return try visibleImages.map { row in
            var work = QueuedWork(prepared: try prepared.fragment(at: row.offset, runID: round.id),
                                  refinement: nil, folder: folder, origin: origin, images: [row])
            work.round = round; work.shortlistOnCompletion = shortlistOnCompletion
            return work
        }
    }
}
