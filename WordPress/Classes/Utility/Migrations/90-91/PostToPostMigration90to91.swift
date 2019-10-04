
/// Copy values of Post or Page's `status` to `statusBeforeUpload`
class PostToPostMigration90to91: NSEntityMigrationPolicy {
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        try super.createRelationships(forDestination: dInstance, in: mapping, manager: manager)

        let status = dInstance.value(forKey: "status")

        dInstance.setValue(status, forKey: "statusBeforeUpload")
    }
}
