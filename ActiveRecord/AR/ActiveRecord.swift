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
    case RecordNotFound(attributes: [String: AnyType])
    case AttributeMissing(record: ActiveRecord, name: String)
    case InvalidAttributeType(record: ActiveRecord, name: String, expectedType: String)
    case ParametersMissing(record: ActiveRecord)
}

func unwrap(any:Any) -> Any {
    
    let mi = Mirror(reflecting: any)
    if mi.displayStyle != .Optional {
        return any
    }
    
    if mi.children.count == 0 { return any }
    let (_, some) = mi.children.first!
    return some
    
}

public typealias ForwardBlock = ((AnyType) -> Any?)
public typealias BacwardBlock = ((Any) -> AnyType?)
public struct Transformer {
    public var forward: ForwardBlock?
    public var backward: BacwardBlock?
    
    public init(forward: ForwardBlock?, backward: BacwardBlock? = nil) {
        self.forward = forward
        self.backward = backward
    }
    public init(backward: BacwardBlock?) {
        self.backward = backward
    }
}

let NSURLTransformer = Transformer(forward: { (value) -> Any? in
    if let url = value as? String {
        return NSURL(string: url)
    }
    return value
    }, backward: { (value) -> AnyType? in
        if let url = value as? NSURL {
            return url.absoluteString
        }
        return value as? AnyType
})

public protocol Transformable {
    static func transformers() -> [String: Transformer]
}

// TODO: Find a way make it as Hashable
public protocol AnyType {
    var dbValue: AnyType { get }
    var rawType: String { get }
    func ==(lhs: AnyType?, rhs: AnyType?) -> Bool
}

extension AnyType {
    public var rawType: String {
        return "\(self)"
    }
    // TODO: Extract as protocol DatabaseRepresatable
    public var dbValue: AnyType {
        return self
    }
}

public func ==(lhs: AnyType?, rhs: AnyType?) -> Bool {
    if let left = lhs {
        if let right = rhs {
            if left.rawType != right.rawType { return false }
            switch left.rawType {
            case "String": return (left as! String) == (right as! String)
            case "Int": return (left as! Int) == (right as! Int)
            case "Float": return (left as! Float) == (right as! Float)
            case "Bool": return (left as! Bool) == (right as! Bool)
            case "ActiveRecord": return (left as? ActiveRecord) == (right as? ActiveRecord)
            default: return false
            }
        }
        return false
    } else if let right = rhs {
        return false
    }
    return true
}

public func ==(l: ActiveRecord?, r: ActiveRecord?) -> Bool {
    return l?.hashValue == r?.hashValue
}

extension String: AnyType {
    public var rawType: String { return "String" }
    public var dbValue: AnyType { return "'\(self)'" }
}
extension Int: AnyType {
    public var rawType: String { return "Int" }
}
extension Float: AnyType {
    public var rawType: String { return "Float" }
}
extension Bool: AnyType {
    public var rawType: String { return "Bool" }
    public var dbValue: AnyType { return Int(self) }
}
extension Double: AnyType {
    public var rawType: String { return "Double" }
}

public typealias Date = NSDate
extension Date: AnyType {
    public var rawType: String { return "Date" }
    public var dbValue: AnyType { return "'\(self)'" }
}

public enum ActiveRecrodAction: Int, Hashable {
    case Initialize
    case Create
    case Update
    case Destroy
    case Save
    
    public var hashValue: Int {
        return self.rawValue
    }
}

public enum Action {
    case Create
    case Update
    case Delete
}

public protocol ActiveRecord: class, AnyType, Transformable {
    var id: AnyType? {set get}
    init()
    init(attributes: [String:AnyType?])
    
    func setAttrbiutes(attributes: [String: AnyType?])
    func getAttributes() -> [String: AnyType?]
    
    static var tableName: String { get }
    static var resourceName: String { get }
    static func acceptedNestedAttributes() -> [String]
    
    // Validators
    func validate(action: Action) -> Errors
    func validators(action: Action) -> [String: Validator]
    
    // Callbackcs
    func before(action: ActiveRecrodAction)
    func after(action: ActiveRecrodAction)
    
    static func before(action: ActiveRecrodAction, callback: ActiveRecordCallback)
    static func after(action: ActiveRecrodAction, callback: ActiveRecordCallback)
}

extension ActiveRecord {
    public static func before(action: ActiveRecrodAction, callback: ActiveRecordCallback) {
        ActiveCallbackStorage.beforeStorage.set(self, action: action, callback: callback)
    }
    public static func after(action: ActiveRecrodAction, callback: ActiveRecordCallback) {
        ActiveCallbackStorage.afterStorage.set(self, action: action, callback: callback)
    }
}

extension ActiveRecord {
    public static func transformers() -> [String: Transformer] {
        return [:]
    }
}

extension ActiveRecord {
    var rawType: String { return "ActiveRecord" }
}

extension ActiveRecord {
    // TODO: Don't have any other opportunities to compare hashes
    var hashValue: AnyType? {
        return self.id
    }
}

extension ActiveRecord {
    public func after(action: ActiveRecrodAction) { }
    public func before(action: ActiveRecrodAction) { }
}

extension ActiveRecord {
    public static var tableName: String {
        let reflect = _reflect(self)
        let projectPackageName = NSBundle.mainBundle() .objectForInfoDictionaryKey("CFBundleExecutable") as! String
        let components = reflect.summary.characters.split(".").map({ String($0) }).filter({ $0 != projectPackageName })
        if let first = components.first {
            if let last = components.last where components.count > 1 {
                return "\(first.lowercaseString)_\(last.lowercaseString.pluralizedString())"
            }
            return first.lowercaseString.pluralizedString()
        }
        return "active_records"
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
    public var errors: Errors {
        if self.isNewRecord {
            return self.validate(.Create)
        } else if self.isDirty {
            return self.validate(.Update)
        }
        return Errors(model: self)
    }
    public var isValid: Bool { return self.errors.isEmpty }
    
    public func validate(action: Action) -> Errors {
        var errors = Errors(model: self)
        let validators = self.validators(action)
        for (attribute, value) in self.attributes {
            if let validator = validators[attribute] {
                validator.validate(self, attribute: attribute, value: value, errors: &errors)
            }
        }
        return errors
    }
    public func validators(action: Action) -> [String: Validator] {
        return [:]
    }
}

extension ActiveRecord {
    public func update(attributes: [String: AnyType?]? = nil) throws -> Bool {
        ActiveCallbackStorage.beforeStorage.get(self.dynamicType, action: .Update).execute(self)
        self.before(.Update)
        // TODO: Add updatable specific attributes
        try UpdateManager(record: self).execute()
        ActiveCallbackStorage.afterStorage.get(self.dynamicType, action: .Update).execute(self)
        self.after(.Update)
        return false
    }
    
    public func update(attribute: String, value: AnyType) throws -> Bool {
        ActiveCallbackStorage.beforeStorage.get(self.dynamicType, action: .Update).execute(self)
        self.before(.Update)
        // TODO: Add updatable specific attributes
        try UpdateManager(record: self).execute()
        ActiveCallbackStorage.afterStorage.get(self.dynamicType, action: .Update).execute(self)
        self.after(.Update)
        return false
    }
    
    public func destroy() throws {
        ActiveCallbackStorage.beforeStorage.get(self.dynamicType, action: .Destroy).execute(self)
        self.before(.Destroy)
        let deleteManager = try DeleteManager(record: self).execute()
        ActiveCallbackStorage.afterStorage.get(self.dynamicType, action: .Destroy).execute(self)
        self.after(.Destroy)
    }
    
    public static func destroy(scope identifier: AnyType?) throws {
        if let id = identifier {
            let record = self.init()
            record.id = identifier
            ActiveCallbackStorage.beforeStorage.get(self, action: .Destroy).execute(record)
            try self.destroy(record)
            ActiveCallbackStorage.afterStorage.get(self, action: .Destroy).execute(record)
        }
    }
    
    public static func destroy(records: [ActiveRecord]) throws {
        if let first = records.first {
            let tableName = first.dynamicType.tableName
            let structure = Adapter.current.structure(tableName)
            if let PK = structure.values.filter({ return $0.PK }).first {
                let values = records.map({ "\($0.attributes[PK.name]!!.dbValue)" }).joinWithSeparator(", ")
                try Adapter.current.connection.execute("DELETE FROM \(tableName) WHERE \(PK.name) IN (\(values));")
            }
        }
    }
    
    public static func destroy(record: ActiveRecord) throws {
        ActiveCallbackStorage.beforeStorage.get(self, action: .Destroy).execute(record)
        try self.destroy([record])
        ActiveCallbackStorage.afterStorage.get(self, action: .Destroy).execute(record)
    }
    
    public func save() throws {
        return try self.save(false)
    }
    
    public static func create(attributes: [String : AnyType?], block: ((AnyObject) -> (Void))? = nil) throws -> Self {
        let record = self.init(attributes: attributes)
        ActiveCallbackStorage.beforeStorage.get(self, action: .Create).execute(record)
        record.before(.Create)
        try record.save(true)
        ActiveCallbackStorage.afterStorage.get(self, action: .Create).execute(record)
        record.after(.Create)
        return record
    }
    
    public static func create() throws -> Self {
        let record = self.init()
        ActiveCallbackStorage.beforeStorage.get(self, action: .Create).execute(record)
        record.before(.Create)
        try record.save(true)
        ActiveCallbackStorage.afterStorage.get(self, action: .Create).execute(record)
        record.after(.Create)
        return record
    }
    
    public static func find(identifier:AnyType) throws -> Self {
        return try self.find(["id" : identifier])
    }
    
    public static func find(attributes:[String: AnyType]) throws -> Self {
        return try ActiveRelation().`where`(attributes).limit(1).execute(true).first!
    }
    
    public static func take(count: Int = 1) throws -> [Self] {
        return try ActiveRelation().limit(count).execute()
    }
    
    public static func first() -> Self? {
        return (try? self.take())?.first
    }
    
    public static func `where`(attributes: [String:AnyType]) -> ActiveRelation<Self> {
        return ActiveRelation().`where`(attributes)
    }
    
    public static func includes(records: ActiveRecord.Type...) -> ActiveRelation<Self> {
        return ActiveRelation().includes(records)
    }
    
    public static func all() throws -> [Self] {
        return try ActiveRelation().execute()
    }
    
    public func save(validate: Bool) throws {
        ActiveCallbackStorage.beforeStorage.get(self.dynamicType, action: .Save).execute(self)
        self.before(.Save)
        if validate && !self.isValid {
            throw ActiveRecordError.RecordNotValid(record: self)
        }
        if self.isNewRecord {
            try InsertManager(record: self).execute()
        } else {
            try UpdateManager(record: self).execute()
        }
        ActiveSnapshotStorage.sharedInstance.set(self)
        ActiveCallbackStorage.afterStorage.get(self.dynamicType, action: .Save).execute(self)
        self.after(.Save)
    }
    
    var isNewRecord: Bool {
        if let id = self.id, let record = try? self.dynamicType.find(["id" : id]) {
            return false
        }
        return true
    }
    
    var isDirty: Bool {
        return !self.dirty.isEmpty
    }
}

extension ActiveRecord {
    public init(attributes: [String:AnyType?]) {
        self.init()
        var merged = self.defaultValues
        for key in attributes.keys {
            if let value = attributes[key] {
                merged[key] = attributes[key]
            }
        }
        print("merged : \(merged)")
        self.setAttrbiutes(merged)
        self.after(.Initialize)
    }
}

extension ActiveRecord {
    public var attributes: [String: AnyType?] {
        get {
            return getAttributes()
        }
        set {
            self.setAttrbiutes(newValue)
            ActiveSnapshotStorage.sharedInstance.set(self)
        }
    }
    public var defaultValues: [String: AnyType?] {
        let attributes = self.attributes
        print("all: \(attributes)")
        var defaultValues = Dictionary<String, AnyType?>()
        for (k, v) in attributes {
            if let value = v {
                defaultValues[k] = value
            }
        }
        print("all: \(defaultValues)")
        return defaultValues
    }
    public var dirty: [String: AnyType?] {
        let snapshot = ActiveSnapshotStorage.sharedInstance.merge(self)
        var dirty = Dictionary<String, AnyType?>()
        let attributes = self.attributes
        for (k, v) in attributes {
            let snapshotEmpty = snapshot[k] == nil
            let valueEmpty = v == nil
            print("\(k): \(snapshot[k]) v: \(v) se: \(snapshotEmpty) ve: \(valueEmpty)")
            if let value = snapshot[k] where (value == v) == false {
                dirty[k] = v
            } else {
                // TODO: Simplify it
                if let sn = snapshot[k], let ssn = sn {
                    if valueEmpty {
                        dirty[k] = ssn
                    }
                } else {
                    if !valueEmpty {
                        dirty[k] = v
                    }
                }
            }
        }
        return dirty
    }
    public func setAttrbiutes(attributes: [String: AnyType?]) {}
    public func getAttributes() -> [String: AnyType?] { return self.transformedAttributes() }
    public func transformedAttributes() -> [String: AnyType?] {
        let reflections = _reflect(self)
        var fields = [String: AnyType?]()
        let transformers = self.dynamicType.transformers()
        for index in 0.stride(to: reflections.count, by: 1) {
            let reflection = reflections[index]
            var result: AnyType?
            var value = unwrap(reflection.1.value)
            if let url = value as? NSURL {
                result = NSURLTransformer.backward?(value)
            } else {
                if let transformer = transformers[reflection.0] {
                    result = transformer.backward?(value)
                } else {
                    result = value as? AnyType
                }
            }
            fields[reflection.0.sneakyString()] = result
        }
        return fields
    }
}

extension ActiveRecord {
    var fields: String {
        return "\(ActiveSerializer(model: self).fields)"
    }
}