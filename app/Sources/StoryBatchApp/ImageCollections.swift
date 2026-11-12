import SwiftUI
import AppKit
import StoryBatchCore

struct ImageSelectionButtons: View {
    @ObservedObject var model: AppModel
    let record: ImageRecord
    let folder: URL
    var allowShortlist = true
    var body: some View {
        HStack(spacing: 6) {
            let shortlisted = model.isShortlisted(record, folder: folder)
            let favorite = model.isFavorite(record, folder: folder)
            Button { model.toggleShortlist(record, folder: folder) } label: {
                Text("📌").opacity(shortlisted ? 1 : 0.45)
            }.help(shortlisted ? "Remove from this batch’s shortlist" : "Add to this batch’s shortlist")
                .accessibilityLabel(shortlisted ? "Remove from shortlist" : "Add to shortlist")
                .disabled(!allowShortlist)
                .background(shortlisted ? Color.accentColor.opacity(0.15) : Color.clear)
            Button { model.toggleFavorite(record, folder: folder) } label: {
                Text(favorite ? "❤️" : "🤍")
            }.help(favorite ? "Remove from favorites across batches" : "Add to favorites across batches")
                .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
            let rejected = model.isRejected(record, folder: folder)
            Button { model.toggleRejected(record, folder: folder) } label: {
                Text(rejected ? "↩️" : "🚫")
            }.help(rejected ? "Restore to this batch’s Images view" : "Reject: hide from this batch’s Images view without deleting files")
                .accessibilityLabel(rejected ? "Restore rejected image" : "Reject image")
                .disabled(!allowShortlist)
        }.disabled(record.status != "completed")
    }
}

struct GalleryImageCard: View {
    @ObservedObject var model: AppModel
    let item: PreviewImageItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if item.record.status == "completed", let image = NSImage(contentsOf: item.folder.appendingPathComponent(item.record.plan.filename)) {
                Button { ImagePreviewController.shared.show(record: item.record, folder: item.folder, model: model) } label: {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 220)
                }.buttonStyle(.plain)
            } else {
                GeometryReader { geometry in
                    let ratio = item.hasRecipe ? CGFloat(max(1, item.record.plan.width)) / CGFloat(max(1, item.record.plan.height)) : 1
                    let width = min(geometry.size.width, geometry.size.height * ratio)
                    VStack(spacing: 10) {
                        if item.record.status == "running" { ProgressView() }
                        else { Image(systemName: "exclamationmark.circle").font(.title) }
                        Text(item.record.status == "completed" ? "Image unavailable" : item.record.status.capitalized).foregroundStyle(.secondary)
                    }
                    .frame(width: width, height: width / ratio)
                    .background(Color.secondary.opacity(0.07))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }.frame(height: 220)
            }
            Text(item.record.plan.filename).font(.caption.monospaced()).lineLimit(3).textSelection(.enabled)
            if item.hasRecipe { ImageRecipeDetails(plan: item.record.plan) }
            Text(item.record.elapsedSeconds.map { "\(item.record.status.capitalized) in \(BatchFormatting.duration($0))" } ?? " ")
                .font(.caption.weight(.medium))
                .accessibilityHidden(item.record.elapsedSeconds == nil)
            ImageSelectionButtons(model: model, record: item.record, folder: item.folder, allowShortlist: item.hasRecipe)
        }.padding(12).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
