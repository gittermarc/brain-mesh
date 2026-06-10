import Foundation
import Testing
@testable import BrainMesh

struct EntitiesHomeDisplaySettingsTests {

    @Test
    func decodesShowCockpitWithFallbackForOldStoredSettings() throws {
        let json = """
        {
          "layout": "list",
          "listStyle": "plain",
          "rowStyle": "titleOnly",
          "density": "standard",
          "showSeparators": true,
          "badgeStyle": "none",
          "metaLine": "none",
          "showAttributeCount": false,
          "showLinkCount": false,
          "showNotesPreview": false,
          "preferThumbnailOverIcon": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EntitiesHomeDisplaySettings.self, from: json)

        #expect(decoded.showCockpit == EntitiesHomeDisplaySettings.default.showCockpit)
    }

    @Test
    func presetsResolveExpectedCockpitDefaults() {
        #expect(EntitiesHomeDisplaySettings.preset(.clean).showCockpit)
        #expect(EntitiesHomeDisplaySettings.preset(.dense).showCockpit == false)
        #expect(EntitiesHomeDisplaySettings.preset(.visual).showCockpit)
        #expect(EntitiesHomeDisplaySettings.preset(.pro).showCockpit)
    }

    @Test
    func optionMetaContainsCockpitToggle() throws {
        let meta = try #require(EntitiesHomeDisplaySettings.optionMeta[.showCockpit])

        #expect(meta.impact == .medium)
        #expect(meta.note?.contains("Home") == true)
    }
}
