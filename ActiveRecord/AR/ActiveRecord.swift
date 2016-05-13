//
//  ActiveRecord.swift
//  ActiveRecord
//
//  Created by Vlad Gorbenko on 4/21/16.
//  Copyright © 2016 Vlad Gorbenko. All rights reserved.
//

import InflectorKit

public enum ActiveRecordError: ErrorType {
    case RecordNotValid(record: ActiveRecord)
    case RecordNotFound(attributes: [String: Any])
    case AttributeMissing(record: ActiveRecord, name: String)
    case InvalidAttributeType(record: ActiveRecord, name: String, expectedType: String)
}

// TODO: Find a way make it as Hashable
public protocol AnyType: Any {
    func ==(lhs: AnyType?, rhs: AnyType?) -> Bool
}

extension AnyType {
    var rawType: String {
        return "\(self)"
    }
}

public func ==(lhs: AnyType?, rhs: AnyType?) -> Bool {
    if lhs?.rawType == rhs?.rawType {
        switch lhs!.rawType {
        case "String": return (lhs as! String) == (rhs as! String)
        case "Int": return (lhs as! Int) == (rhs as! Int)
        case "Float": return (lhs as! Float) == (rhs as! Float)
        default: return false
        }
    }
    return false
}

extension String: AnyType {
    var rawType: String { return "String" }
}
extension Int: AnyType {
    var rawType: String { return "Int" }
}
extension Float: AnyType {
    var rawType: String { return "Float" }
}

public protocol ActiveRecord {
    var id: AnyType? {set get}
    init()
    init(attributes: [String:Any?])
    
    func setAttrbiutes(attributes: [String: Any?])
    func getAttributes() -> [String: Any?]
    
    static var tableName: String { get }
    static var resourceName: String { get }
    static func acceptedNestedAttributes() -> [String]
    
    public func validate() -> Bool
    public func validators() -> [String: Validator]
}

extension ActiveRecord {
    public static var tableName: String {
        var className = "\(self.dynamicType)"
        if let typeRange = className.rangeOfString(".Type") {
            className.replaceRange(typeRange, with: "")
        }
        return className.lowercaseString.pluralizedString()
    }
    
    public static var resourceName: String {
        return self.modelName
    }
    
    public final static var modelName: String {
        var className = "\(self.dynamicType)"
        if let typeRange = className.rangeOfString(".Type") {
            className.replaceRange(typeRange, with: "")
        }
        return className.lowercaseString
    }
    
    public static func acceptedNestedAttributes() -> [String] { return [] }
}


extension ActiveRecord {
    public var isValid: Bool { return self.validate() }
    
    public func validate() -> Bool {
        return true
    }
    
    public func validators() -> [String: Validator] {
        return [:]
    }
}

extension ActiveRecord {
    public func update(attributes: [String: Any?]) throws -> Bool {
        // TODO: get diff between model snapshot and passed attributes
        try ActiveRelation(model: self).update(attributes)
        // TODO: update model attributes
        return false
    }
    
    public func update(attribute: String, value: Any) throws -> Bool {
        try ActiveRelation(model: self).update([attribute: value])
        // TODO: update model attributes
        return false
    }
    
    public func destroy() throws -> Bool {
        return false
    }
    
    public func save() throws -> Bool {
        return try self.save(false)
    }
    
    public static func create(attributes: [String : Any?], block: ((AnyObject) -> (Void))? = nil) throws -> Self {
        let record = self.init(attributes: attributes)
        try record.save(true)
        return record;
    }
    
    public static func find(identifier:Any) throws -> Self {
        return try self.find(["id" : identifier])
    }
    
    public static func find(attributes:[String:Any]) throws -> Self {
        return try ActiveRelation().`where`(attributes).limit(1).execute(true).first!
    }
    
    public static func take(count: Int = 1) throws -> [Self] {
        return try ActiveRelation().limit(count).execute()
    }
    
    public static func `where`(attributes: [String:Any]) -> ActiveRelation<Self> {
        return ActiveRelation().`where`(attributes)
    }
    
    public static func all() throws -> [Self] {
        return try ActiveRelation().execute()
    }
    
    public func save(validate: Bool) throws -> Bool {
        if validate && !self.isValid {
            throw ActiveRecordError.RecordNotValid(record: self)
        }
        let result = try ActiveRelation(model: self).update()
        ActiveSnapshotStorage.sharedInstance.set(self)
        return result
    }
}

extension ActiveRecord {
    public init(attributes: [String:Any?]) {
        self.init()
        self.attributes = attributes
    }
}

extension ActiveRecord {
    public var attributes: [String: Any?] {
        get {
            return getAttributes()
        }
        set {
            self.setAttrbiutes(newValue)
            ActiveSnapshotStorage.sharedInstance.set(self)
        }
    }
    public func setAttrbiutes(attributes: [String: Any?]) {}
    public func getAttributes() -> [String: Any?] {
        let reflections = _reflect(self)
        
        var fields = [String: Any?]()
        for index in 0.stride(to: reflections.count, by: 1) {
            let reflection = reflections[index]
            fields[reflection.0] = reflection.1.value
        }
        return fields
    }
}

extension ActiveRecord {
    var fields: String {
        return "\(ActiveSerializer(model: self).fields)"
    }
}