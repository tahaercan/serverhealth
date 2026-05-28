import Foundation
import SwiftData

/// SwiftData schema **version 1** — the initial published schema.
///
/// Every `@Model` type the app persists is listed in `models`. SwiftData uses
/// this list to build the underlying store on first launch, and the migration
/// plan uses it as the "from" or "to" side of each migration stage.
///
/// **Evolving the schema:**
///   1. Create a new file `ServerHealthSchemaV2.swift` declaring the v2 models.
///      Either nest the changed models inside the V2 enum (canonical pattern)
///      or keep top-level types and rename the v1 copies inside this enum.
///   2. Bump `versionIdentifier`.
///   3. Append a `MigrationStage` to `ServerHealthMigrationPlan.stages`:
///      - `.lightweight(fromVersion:toVersion:)` for additive changes
///        (new optional fields, new model types) — SwiftData handles
///        these automatically without data loss.
///      - `.custom(...)` for breaking changes (renames, type changes,
///        removed fields) — you write `willMigrate` / `didMigrate` closures
///        that transform existing rows.
///   4. **Never modify this V1 enum after release** — it is the historical
///      record of what was on disk for v1 users.
enum ServerHealthSchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Server.self,
            MonitoringRule.self,
            MetricSnapshot.self,
            LogEntry.self,
        ]
    }
}

/// Ordered list of every schema version the app has ever shipped, plus the
/// migration stages that move data between consecutive versions.
///
/// SwiftData inspects the existing store at launch, finds its version, then
/// applies every migration stage from there up to the latest version in
/// `schemas`. If the store is brand-new it just uses the latest schema
/// directly.
///
/// Right now only V1 exists, so `stages` is empty. The first real migration
/// (V1 → V2) will add the first stage here.
enum ServerHealthMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [
            ServerHealthSchemaV1.self,
        ]
    }

    static var stages: [MigrationStage] {
        // No stages yet — V1 is the initial schema, nothing to migrate from.
        // When V2 lands, append:
        //   .lightweight(fromVersion: ServerHealthSchemaV1.versionIdentifier,
        //                toVersion:   ServerHealthSchemaV2.versionIdentifier)
        []
    }
}
