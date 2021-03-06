
//
//  MigrationsController.swift
//  AR
//
//  Created by Vlad Gorbenko on 5/1/16.
//  Copyright © 2016 Vlad Gorbenko. All rights reserved.
//

public class MigrationsController {
    
    class SchemaMigration: ActiveRecord {
        class var tableName: String {
            return "schema_migrations"
        }
        class func getTableName() -> String {
            return "schema_migrations"
        }
        var id: AnyType?
        var name: String!
        required init() {}
        
        func setAttrbiutes(attributes: [String: AnyType?]) {
            self.name = attributes["name"] as! String
        }
    }
    
    public static var sharedInstance = MigrationsController()
    
    public var migrations = Array<Migration>()
    
    public var tables = Array<Table>()
    
    //MARK: - Lifecycle
    
    public init() {}
    
    //MARK: - Setup
    
    public func setup() {
        SchemasMigration().up()
    }
    
    //MARK: - Migration management
    
    public func migrate() {
        self.migrations.sortInPlace({ $0.timestamp < $1.timestamp })
        let passed = try! SchemaMigration.all()
        let difference = Set(self.migrations.map({ $0.id })).subtract(Set(passed.map({ $0.name })))
        let pending = self.migrations.filter({ difference.contains($0.id) })
        for migration in pending {
            if self.isFailed == false {
                migration.up()
                if self.isFailed == false {
                    let shemaMigration = SchemaMigration(attributes: ["name" : migration.id ])
                    do {
                        try shemaMigration.save()
                    } catch {
                        print("MIGRATION: \(migration) IS NOT SAVED: \(error)")
                    }
                }
            }
        }
    }
    
    public func up(migration: Migration) {
        migration.up()
    }
    
    public func down(migration: Migration) {
        migration.down()
    }
    
    //MARK: - Utils
    private var isFailed = false
    func check(block: ((Void) throws -> (Void))) {
        do {
            try block()
        } catch {
            print("\(error)")
            self.isFailed = true
        }
    }
    
}

func ==(lhs: MigrationsController.SchemaMigration, rhs: MigrationsController.SchemaMigration) -> Bool {
    return lhs.name == rhs.name
}
