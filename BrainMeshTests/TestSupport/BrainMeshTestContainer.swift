import SwiftData
@testable import BrainMesh

struct BrainMeshTestStore {
    let container: ModelContainer
    let context: ModelContext
}

enum BrainMeshTestContainer {
    static let schema = Schema([
        MetaGraph.self,
        MetaEntity.self,
        MetaAttribute.self,
        MetaLink.self,
        MetaAttachment.self,
        MetaDetailFieldDefinition.self,
        MetaDetailFieldValue.self,
        MetaDetailsTemplate.self
    ])

    static func makeInMemoryStore(autosaveEnabled: Bool = false) throws -> BrainMeshTestStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = makeContext(for: container, autosaveEnabled: autosaveEnabled)
        return BrainMeshTestStore(container: container, context: context)
    }

    static func makeContext(for container: ModelContainer, autosaveEnabled: Bool = false) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = autosaveEnabled
        return context
    }
}
