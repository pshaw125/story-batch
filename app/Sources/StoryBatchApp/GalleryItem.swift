import Foundation
import StoryBatchCore

struct PreviewImageItem: Identifiable {
    let record: ImageRecord
    let folder: URL
    let hasRecipe: Bool
    var id: String { SavedImageSelection.identity(folder: folder, filename: record.plan.filename) }
    init(record: ImageRecord, folder: URL, hasRecipe: Bool) { self.record = record; self.folder = folder; self.hasRecipe = hasRecipe }
    init(favorite: FavoriteImage) {
        folder = favorite.url.deletingLastPathComponent(); hasRecipe = favorite.record != nil
        if let saved = favorite.record { record = saved }
        else {
            let p = ImagePlan(number: 0, seed: 0, shift: try! ShiftValue("1"), steps: 0, width: 0, height: 0, prompt: "", filename: favorite.url.lastPathComponent)
            var placeholder = ImageRecord(plan: p); placeholder.status = "completed"; record = placeholder
        }
    }
}
