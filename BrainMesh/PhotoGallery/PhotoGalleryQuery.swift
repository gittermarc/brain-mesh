//
//  PhotoGalleryQuery.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.02.26.
//

import Foundation
import SwiftUI
import SwiftData

/// Shared query builders for the detail-only photo gallery.
///
/// Keeping the predicates in one place avoids subtle drift between
/// Section/Browser/Viewer and makes future changes (e.g. scoping rules)
/// much safer.
enum PhotoGalleryQueryBuilder {

    /// Query for all detail-only gallery images of a specific owner.
    static func galleryImagesQuery(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?
    ) -> Query<MetaAttachment, [MetaAttachment]> {
        let kindRaw = ownerKind.rawValue
        let oid = ownerID
        let galleryRaw = AttachmentContentKind.galleryImage.rawValue

		// IMPORTANT: keep predicates store-translatable (avoid OR / optional tricks).
		let predicate: Predicate<MetaAttachment>
		if let gid = graphID {
			predicate = #Predicate { a in
				a.ownerKindRaw == kindRaw &&
				a.ownerID == oid &&
				a.graphID == gid &&
				a.contentKindRaw == galleryRaw
			}
		} else {
			predicate = #Predicate { a in
				a.ownerKindRaw == kindRaw &&
				a.ownerID == oid &&
				a.contentKindRaw == galleryRaw
			}
		}

		return Query<MetaAttachment, [MetaAttachment]>(
			filter: predicate,
			sort: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
		)
    }

    /// FetchDescriptor for legacy attachments that might actually be images,
    /// scoped to this owner.
    ///
    /// We keep the actual "is image" check in the action (UTType conforms).
    static func legacyImageMigrationCandidates(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?
    ) -> FetchDescriptor<MetaAttachment> {
        let kindRaw = ownerKind.rawValue
        let oid = ownerID
        let galleryRaw = AttachmentContentKind.galleryImage.rawValue

		let predicate: Predicate<MetaAttachment>
		if let gid = graphID {
			predicate = #Predicate { a in
				a.ownerKindRaw == kindRaw &&
				a.ownerID == oid &&
				a.graphID == gid &&
				a.contentKindRaw != galleryRaw
			}
		} else {
			predicate = #Predicate { a in
				a.ownerKindRaw == kindRaw &&
				a.ownerID == oid &&
				a.contentKindRaw != galleryRaw
			}
		}

		return FetchDescriptor<MetaAttachment>(predicate: predicate)
    }
}
