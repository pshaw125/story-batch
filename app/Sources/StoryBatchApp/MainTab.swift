enum MainTab: Int, CaseIterable, Identifiable {
    case preview, images, activity, queue, shortlist, favorites, rejected
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .preview: return "Preview"
        case .images: return "Images"
        case .activity: return "Activity"
        case .queue: return "Queue"
        case .shortlist: return "Shortlist"
        case .favorites: return "Favorites"
        case .rejected: return "Rejected"
        }
    }
}
