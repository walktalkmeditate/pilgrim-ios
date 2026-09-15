// Pilgrim/Models/Honor/MapboxTileRegionLoader.swift
import Foundation

/// Filled in by the production-conformer task; until then a loader that
/// holds nothing, so the app builds and every test uses the fake.
final class MapboxTileRegionLoader: TileRegionLoading {
    final class Handle: TileLoadHandle { func cancel() {} }
    func hasStylePack(_ pack: StylePackRequest) -> Bool { false }
    func loadStylePack(_ pack: StylePackRequest, completion: @escaping (Result<Void, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        completion(.failure(.failed)); return Handle()
    }
    func loadRegion(_ request: TileRegionRequest, progress: @escaping (Int, Int) -> Void,
                    completion: @escaping (Result<TileRegionSummary, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        completion(.failure(.failed)); return Handle()
    }
    func regions() -> [TileRegionSummary] { [] }
    func removeRegion(id: String) {}
}
