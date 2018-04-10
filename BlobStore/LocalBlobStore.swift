//
//  LocalBlobStore.swift
//  BlobStore
//
//  Copyright 2013 Kashoo Cloud Accounting Inc.
//  Copyright 2018 Kashoo Systems Inc.
//

import Foundation

public class LocalBlobStore: BlobStore {

    // These are the names of filesystem extended attributes in which we store the source blob's metadata.
    static let kMimeTypeXattrName = "com.kashoo.MIMEType"; // MIME type
    static let kFilenameXattrName = "com.kashoo.Filename"; // original filename

    let storeDirectoryURL: URL
    
    public init(storeDirectoryURL: URL) {
        self.storeDirectoryURL = storeDirectoryURL
        
        // Create the directory if it doesn't exist.
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: storeDirectoryURL.path) {
            try! fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    // MARK: - BlobStore protocol

    public func store(_ blobIdentifier: String,
                      contentsOf url: URL,
                      filename: String,
                      mimeType: String,
                      completion: @escaping (Bool, Error?) -> ()) {
        store(blobIdentifier: blobIdentifier,
              filename: filename,
              mimeType: mimeType,
              using: { targetURL in
                try FileManager.default.copyItem(at: url, to: targetURL)
        }, completion: completion)
    }
        
    public func store(_ blobIdentifier: String,
                      data: Data,
                      filename: String,
                      mimeType: String,
                      completion: @escaping (Bool, Error?) -> ()) {
        store(blobIdentifier: blobIdentifier,
              filename: filename,
              mimeType: mimeType,
              using: { targetURL in
                try data.write(to: targetURL, options: .withoutOverwriting)
        }, completion: completion)
    }
    
    public func fetchData(for blobIdentifier: String) -> Data? {
        guard let url = fetchURL(for: blobIdentifier),
            let data = try? Data(contentsOf: url) else {
                return nil
        }
        return data
    }
    
    public func fetchData(for blobIdentifier: String,
                   completion: @escaping (Data?, Error?) -> ()) {
        completion(fetchData(for: blobIdentifier), nil)
    }
    
    public func fetchURL(for blobIdentifier: String) -> URL? {
        // Contract states that we return a URL only for a file that exists.
        let url = nominalFileURL(for: blobIdentifier)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    public func fetchURL(for blobIdentifier: String,
                         completion: @escaping (URL?, Error?) -> ()) {
        completion(fetchURL(for: blobIdentifier), nil)
    }
    
    public func metadata(for blobIdentifier: String) -> BlobMetadata? {
        guard let attribs = try? FileManager.default.attributesOfItem(atPath: nominalFileURL(for: blobIdentifier).path),
            let size = attribs[.size] as? Int,
            let filename: String = (try? fileAttribute(LocalBlobStore.kFilenameXattrName, for: blobIdentifier)) ?? nil,
            let mimeType: String = (try? fileAttribute(LocalBlobStore.kMimeTypeXattrName, for: blobIdentifier)) ?? nil else {
                return nil
        }
        
        return BlobMetadata(size: size,
                            filename: filename,
                            mimeType: mimeType)
    }
    
    public func metadata(for blobIdentifier: String,
                  completion: @escaping (BlobMetadata?, Error?) -> ()) {
        completion(metadata(for: blobIdentifier), nil)
    }
    
    public func delete(_ blobIdentifier: String) throws {
        try FileManager.default.removeItem(at: nominalFileURL(for: blobIdentifier))
    }

    public func shutDown(immediately: Bool) {
        // Nothing to do.
    }

    // MARK: - Other general API

    internal func store(blobIdentifier: String,
                        filename: String,
                        mimeType: String,
                        using storeHandler: (URL) throws -> (),
                        completion: @escaping (Bool, Error?) -> ()) {
        do {
            try storeHandler(nominalFileURL(for: blobIdentifier))
            try setFileAttribute(LocalBlobStore.kMimeTypeXattrName, value: mimeType, for: blobIdentifier)
            try setFileAttribute(LocalBlobStore.kFilenameXattrName, value: filename, for: blobIdentifier)
            completion(true, nil)
        }
        catch {
            NSLog("Local blob store failed to store blob payload on disk: %@", String(describing: error))
            completion(false, error)
        }
    }
    
    var allBlobIdentifiers: Set<String> {
        var blobIdentifiers = Set<String>()
        for url in try! FileManager.default.contentsOfDirectory(at: storeDirectoryURL,
                                                                includingPropertiesForKeys: nil,
                                                                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        {
            // The blob identifier is currently represented in the filename itself.
            blobIdentifiers.insert(url.pathComponents.last!)
        }
        return blobIdentifiers
    }
    
    func nominalFileURL(for blobIdentifier: String) -> URL {
        return storeDirectoryURL.appendingPathComponent(blobIdentifier)
    }

    // MARK: - Utilities for getting/setting filesystem extended attributes

    func fileAttribute(_ attribute: String,
                       for blobIdentifier: String) throws -> Data? {
        let url = nominalFileURL(for: blobIdentifier)
        let data = try url.withUnsafeFileSystemRepresentation { fileSystemPath -> Data? in
            let size = getxattr(fileSystemPath, attribute, nil, 0, 0, 0)
            guard size >= 0 else { return nil }
            
            var data = Data(count: size)
            let count = data.count
            let result = data.withUnsafeMutableBytes { pointer -> Int in
                return getxattr(fileSystemPath, attribute, pointer, count, 0, 0)
            }
            
            guard result >= 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                              userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
            }
            return data
        }
        
        return data
    }
    
    func fileAttribute(_ attribute: String,
                       for blobIdentifier: String) throws -> String? {
        guard let data: Data = try fileAttribute(attribute, for: blobIdentifier) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    func setFileAttribute(_ attribute: String,
                          value data: Data,
                          for blobIdentifier: String) throws {
        let url = nominalFileURL(for: blobIdentifier)
        try url.withUnsafeFileSystemRepresentation { fileSystemPath -> Void in
            let err = data.withUnsafeBytes { pointer -> Int32 in
                return setxattr(fileSystemPath, attribute, pointer, data.count, 0, 0)
            }
            
            guard err == noErr else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                              userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
            }
        }
    }
    
    func setFileAttribute(_ attribute: String,
                          value string: String,
                          for blobIdentifier: String) throws {
        try setFileAttribute(attribute,
                             value: string.data(using: .utf8)!,
                             for: blobIdentifier)
    }
}
