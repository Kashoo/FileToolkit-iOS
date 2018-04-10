//
//  RemoteCachingBlobStore.swift
//  Shoebox
//
//  Created by Ben Kennedy on 2018-01-19. Ported from the Kashoo-iPad Blob Store suite originally created in 2013.
//  Copyright © 2018 Kashoo Cloud Accounting Inc. All rights reserved.
//

import Alamofire

public class RemoteCachingBlobStore: RemoteBlobStore {

    // This is the name of a filesystem extended attribute in which we store the source data's MIME type.
    let kLastAccessDateXattrName = "com.kashoo.LastAccessDate"
    
    // The following values govern when and how the cache-pruning mechanism works.
    //
    // Maximum number of bytes to which the cache size will be restricted, regardless of device free space.
    var maximumCacheSize = (500 * 1024 * 1024)
    // Number of free bytes on the filesystem at or below which cache pruning will be forced.
    var cachePruningMinimumDeviceFree = (100 * 1024 * 1024)
    // Number of free bytes that we will attempt to make available (net) as a result of pruning the cache.
    var cachePruningTargetDeviceFree = (200 * 1024 * 1024)

    let localCacheBlobStore: LocalBlobStore
    
    weak var periodicPruneTimer: Timer?
    
    /// - parameters:
    ///    - sessionManager: A session manager to use for networking calls.
    ///    - remoteStoreBaseURL: A remote URL pointing to the remote blob store server (typically `http` or `https`).
    ///    - cacheDirectoryURL: A local URL for a directory to use as the local download cache. Will be created if not already extant.
    ///    - cachePruningInterval: The repeating duty cycle at which to conduct a cache cleanup, or 0 to disable automatic pruning.
    ///
    public init(sessionManager: SessionManager,
                remoteStoreBaseURL: URL,
                cacheDirectoryURL: URL,
                cachePruningInterval: TimeInterval) {
        localCacheBlobStore = LocalBlobStore(storeDirectoryURL: cacheDirectoryURL)
        
        super.init(sessionManager: sessionManager, baseURL: remoteStoreBaseURL)

        if (cachePruningInterval > 0) {
            self.pruneCache()
            periodicPruneTimer = Timer.scheduledTimer(withTimeInterval: cachePruningInterval, repeats: true) { _ in
                self.pruneCache()
            }
        }
    }
    
    // MARK: - BlobStore protocol
    
    // Note: we do NOT write to the cache on store, but rather only on retrieve.  This permits:
    // a) testing of the network round-trip,
    // b) more efficient file movement (from local -> remote caches) when managed/implemented by SmartBlobStore.

    public override func fetchData(for blobIdentifier: String) -> Data? {
        guard let data = localCacheBlobStore.fetchData(for: blobIdentifier) else {
            return nil
        }
        touchLastAccessDate(for: blobIdentifier)
        return data
    }
    
    public override func fetchData(for blobIdentifier: String,
                                   completion: @escaping (Data?, Error?) -> ()) {
        // First, attempt to obtain the blob from the cache.
        guard let data = fetchData(for: blobIdentifier) else {
            // Schedule a retrieval over the network by calling our sibling URL-based method.
            fetchURL(for: blobIdentifier) { (url, error) in
                // The file will now exist, presuming that the retrieval was successful.
                let data = self.fetchData(for: blobIdentifier)
                completion(data, error)
            }
            return
        }
        completion(data, nil)
    }
    
    public override func fetchURL(for blobIdentifier: String) -> URL? {
        guard let url = localCacheBlobStore.fetchURL(for: blobIdentifier) else {
            return nil
        }
        touchLastAccessDate(for: blobIdentifier)
        return url
    }
    
    public override func fetchURL(for blobIdentifier: String,
                                  completion: @escaping (URL?, Error?) -> ()) {
        // First, attempt to obtain the blob from the cache.
        if let url = fetchURL(for: blobIdentifier) {
            completion(url, nil)
            return
        }
        
        // Schedule a retrieval over the network for saving into the local store.
        let fileURL = self.localCacheBlobStore.nominalFileURL(for: blobIdentifier)
        
        sessionManager.download(baseURL.appendingPathComponent(blobIdentifier),
                                method: .get,
                                to: { _,_ in return (fileURL, .removePreviousFile) })
            .responseData { response in
                guard response.result.isSuccess,
                    let headers = response.response?.allHeaderFields,
                    let metadata = RemoteBlobStore.metadata(fromHeaders: headers) else {
                        completion(nil, response.error)
                        return
                }
                
                // Finalize the data in the local cache for subsequent hits. The file data is already there; we only need to set the metadata.
                self.localCacheBlobStore.store(blobIdentifier: blobIdentifier,
                                               filename: metadata.filename,
                                               mimeType: metadata.mimeType,
                                               using: { _ in return }, // do nothing.
                    completion:
                    { (success, error) in
                        guard success else {
                            completion(fileURL, error)
                            return
                        }
                        
                        self.touchLastAccessDate(for: blobIdentifier)
                        self.pruneCache()
                        completion(fileURL, nil)
                })
        }
    }
    
    public override func metadata(for blobIdentifier: String) -> BlobMetadata? {
        return localCacheBlobStore.metadata(for: blobIdentifier)
    }
    
    public override func metadata(for blobIdentifier: String,
                                  completion: @escaping (BlobMetadata?, Error?) -> ()) {
        guard let metadata = localCacheBlobStore.metadata(for: blobIdentifier) else {
            super.metadata(for: blobIdentifier, completion: completion)
            return
        }
        completion(metadata, nil)
    }

    public override func delete(_ blobIdentifier: String) throws {
        try super.delete(blobIdentifier)
        try localCacheBlobStore.delete(blobIdentifier)
    }
    
    public override func shutDown(immediately: Bool) {
        periodicPruneTimer?.invalidate()
        localCacheBlobStore.shutDown(immediately: immediately)
        super.shutDown(immediately: immediately)
    }
    
    // MARK: - Internal utilities
    
    func touchLastAccessDate(for blobIdentifier: String) {
        var referenceInterval = Date.timeIntervalSinceReferenceDate
        try? localCacheBlobStore.setFileAttribute(kLastAccessDateXattrName,
                                                  value: Data(bytes: &referenceInterval, count: MemoryLayout<TimeInterval>.size),
                                                  for: blobIdentifier)
    }
    
    func lastAccessDate(for blobIdentifier: String) -> Date? {
        var lastAccess: Date?
        do {
            if let buffer: Data = try localCacheBlobStore.fileAttribute(kLastAccessDateXattrName, for: blobIdentifier) {
                var referenceInterval = TimeInterval()
                (buffer as NSData).getBytes(&referenceInterval, length: MemoryLayout<TimeInterval>.size)
                lastAccess = Date(timeIntervalSinceReferenceDate: referenceInterval)
            }
        }
        catch {}
        return lastAccess;
    }

    // Evaluate our current disk cache usage, and dump payloads for last-recently-accessed blobs as conditions may warrant.
    // This workhorse loop is invoked periodically in various circumstances.
    func pruneCache() {
        let keyBlobIdent = "blobIdentifier"
        let keyFileURL = "fileURL"
        let keyFileSize = "fileSize"
        let keyLastAccess = "lastAccessDate"

        let fileManager = FileManager.default
        let fileURLs: [URL]
        
        // Fetch file URLs for all cached blob payloads present on disk and enumerate them.
        do {
            fileURLs = try fileManager.contentsOfDirectory(at: localCacheBlobStore.storeDirectoryURL,
                                                           includingPropertiesForKeys: [.fileAllocatedSizeKey],
                                                           options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        
            var blobArray = [[String : Any]]()
            var totalCacheSize: Int = 0
            
            for url in fileURLs {
                // The blob identifier is currently represented in the filename itself.
                let blobIdentifier = url.pathComponents.last!
                
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = resourceValues.fileSize ?? 0
                let lastAccess = lastAccessDate(for: blobIdentifier) ?? Date()
                
                totalCacheSize += fileSize
                
                // Store a dictionary that describes several properties relating to this blob.
                blobArray.append([
                    keyFileURL : url,
                    keyBlobIdent : blobIdentifier,
                    keyFileSize : fileSize,
                    keyLastAccess : lastAccess,
                    ])
            }
            // Ascertain the current free space on the device, and see if a pruning cycle is warranted.
            let dict = try fileManager.attributesOfFileSystem(forPath: localCacheBlobStore.storeDirectoryURL.path)
            let totalFreeBytes = (dict[FileAttributeKey.systemFreeSize] as! NSNumber).intValue
            
            NSLog("Remote cache blob store occupies %lld bytes (%lld max, %lld device free)", totalCacheSize, maximumCacheSize, totalFreeBytes);
            
            let bytesToPurge: Int
            if totalCacheSize > maximumCacheSize {
                bytesToPurge = (totalCacheSize - maximumCacheSize)
            }
            else if totalFreeBytes <= cachePruningMinimumDeviceFree {
                bytesToPurge = (cachePruningTargetDeviceFree - totalFreeBytes);
            }
            else {
                bytesToPurge = 0
            }
            
            if bytesToPurge > 0 {
                // Sort the array into candidate purge order on the basis of last-accessed times (and file sizes, in case of a tie).
                blobArray.sort { (dict1, dict2) -> Bool in
                    if (dict1[keyLastAccess] as! Date) < (dict2[keyLastAccess] as! Date) {
                        return true
                    } else if (dict1[keyLastAccess] as! Date) == (dict2[keyLastAccess] as! Date) {
                        return (dict1[keyFileSize] as! Int) > (dict2[keyFileSize] as! Int)
                    } else {
                        return false
                    }
                }
                
                var bytesPurged: Int = 0
                
                for dict in blobArray {
                    if bytesPurged >= bytesToPurge {
                        break
                    }
                    
                    try fileManager.removeItem(at: dict[keyFileURL] as! URL)
                    bytesPurged += dict[keyFileSize] as! Int
                    let minutesAgo = Int(Date().timeIntervalSince(dict[keyLastAccess] as! Date) / 60)
                    NSLog("Remote cache blob store disposed of %@ (%@ bytes, last accessed %ld mins ago)", dict[keyBlobIdent] as! String, dict[keyFileSize] as! NSNumber, minutesAgo);
                }
                
                NSLog("Remote cache blob store pruned %lld bytes from local cache", bytesPurged);
            }
        }

        catch {
            NSLog("A filesystem error occurred; cache pruning aborted: %@", String(describing: error))
            return
        }
    }
}
