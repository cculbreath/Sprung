//
//  TransformerRegistry.swift
//  PhysCloudResume
//
//  Created to consolidate Core Data / SwiftData value transformer registration.
//

import Foundation

/// Central registry for value transformers used by SwiftData models.
enum TransformerRegistry {
    static func registerTransformers() {
        ValueTransformer.setValueTransformer(
            TreeNodeStringArrayTransformer(),
            forName: TreeNode.schemaValidationOptionsTransformerName
        )
        ValueTransformer.setValueTransformer(
            ResumeStringDictionaryTransformer(),
            forName: Resume.keyLabelsTransformerName
        )
    }
}

@objc(TreeNodeStringArrayTransformer)
final class TreeNodeStringArrayTransformer: NSSecureUnarchiveFromDataTransformer {
    override class var allowedTopLevelClasses: [AnyClass] {
        [NSArray.self, NSString.self]
    }
}

@objc(ResumeStringDictionaryTransformer)
final class ResumeStringDictionaryTransformer: NSSecureUnarchiveFromDataTransformer {
    override class var allowedTopLevelClasses: [AnyClass] {
        [NSDictionary.self, NSString.self]
    }
}
