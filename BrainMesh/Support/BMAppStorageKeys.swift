//
//  BMAppStorageKeys.swift
//  BrainMesh
//
//  Centralized UserDefaults/@AppStorage keys.
//  Added in PR 01 to reduce stringly-typed keys spread across the codebase.
//

enum BMAppStorageKeys {

    // MARK: - Global graph/session

    static let activeGraphID = "BMActiveGraphID"

    // MARK: - Onboarding

    static let onboardingHidden = "BMOnboardingHidden"
    static let onboardingCompleted = "BMOnboardingCompleted"
    static let onboardingAutoShown = "BMOnboardingAutoShown"

    // MARK: - Hydrators

    static let imageHydratorLastAutoRun = "BMImageHydratorLastAutoRun"

    // MARK: - Entities / attributes

    static let entitiesHomeSort = "BMEntitiesHomeSort"
    static let entityAttributeSortMode = "BMEntityAttributeSortMode"

    static let entityAttributesAllSort = "BMEntityAttributesAllSort"
    static let entityAttributesAllShowPinnedDetails = "BMEntityAttributesAllShowPinnedDetails"
    static let entityAttributesAllShowNotesPreview = "BMEntityAttributesAllShowNotesPreview"

    // MARK: - Icons

    static let recentSymbolNames = "BMRecentSymbolNames"

    // MARK: - Appearance

    static let appearanceSettingsV1 = "BMAppearanceSettingsV1"

    // MARK: - Display

    static let displaySettingsV1 = "BMDisplaySettingsV1"

    // MARK: - Video import

    static let compressVideosOnImport = "BMCompressVideosOnImport"
    static let videoCompressionQuality = "BMVideoCompressionQuality"
}
