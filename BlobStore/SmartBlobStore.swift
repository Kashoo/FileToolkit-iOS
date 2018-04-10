//
//  SmartBlobStore.swift
//  BlobStore
//
//  Copyright 2013 Kashoo Cloud Accounting Inc.
//  Copyright 2018 Kashoo Systems Inc.
//

import Alamofire

public class SmartBlobStore: BlobStore {

    // These notifications are posted when a deferred store to the remote blob store fails for an unexpected reason.
    static let kRemoteUploadFailedNotificationName = Notification.Name(rawValue: "SmartAttachmentBlobStoreRemoteUploadFailedNotification")
    // The dictionary key in the preceding notification's userInfo that provides the associated Error.
    static let kErrorKey = "error"

    let localBlobStore: LocalBlobStore! // Holds blobs that are awaiting upsync to the server. Intended to be somewhere within the user's Documents directory in order to be backed up as usual with regular iPad device backups.
    let remoteBlobStore: RemoteCachingBlobStore!

    /// Determines on what basis the `store(…)` methods call their provided completion handler.
    ///
    /// When `true`, completion is based on the success of the initial local (durable) store; upload to the remote store is then managed asynchronously and reported via notification. This is the default.
    ///
    /// When `false`, completion is based on the result of the remote store operation (provided that local first succeeded). This is useful for unit testing where indeterminate asynchronous effects cause problems.
    ///
    var completesImmediatelyAfterLocalStore = true

    var blobsQueuedForUpload = Set<String>()

    /// - parameters:
    ///    - sessionManager: A session manager to use for networking calls.
    ///    - localQueueDirectory: A local URL for a directory in which to durably store blobs prior to uploading them to the remote server. Will be created if not already extant.
    ///    - remoteCacheDirectory: A local URL for a directory to use as the purgable download cache for the remote store.
    ///    - remoteStoreBaseURL: A remote URL pointing to the remote blob store server.
    ///    - cachePruningInterval: The repeating duty cycle at which to conduct a remote cache cleanup, or 0 to disable automatic pruning. Default is 1800 (30 minutes).
    ///
    public init(sessionManager: SessionManager,
                localQueueDirectory: URL,
                remoteCacheDirectory: URL,
                remoteStoreBaseURL: URL,
                cachePruningInterval: TimeInterval = (30 * 60)) {
        self.localBlobStore = LocalBlobStore(storeDirectoryURL: localQueueDirectory)
        self.remoteBlobStore = RemoteCachingBlobStore(sessionManager: sessionManager,
                                                      remoteStoreBaseURL: remoteStoreBaseURL,
                                                      cacheDirectoryURL: remoteCacheDirectory,
                                                      cachePruningInterval: cachePruningInterval)
        
        uploadAllLocalBlobs() // Process any pending local queue
    }

    // MARK: - BlobStore protocol

    public func store(_ blobIdentifier: String,
                      data: Data,
                      filename: String,
                      mimeType: String,
                      completion: @escaping (Bool, Error?) -> ()) {
        localBlobStore.store(blobIdentifier,
                             data: data,
                             filename: filename,
                             mimeType: mimeType,
                             completion: storeDataCompletionHandler(for: blobIdentifier,
                                                                    clientCompletion: completion))
    }

    public func store(_ blobIdentifier: String,
                      contentsOf url: URL,
                      filename: String,
                      mimeType: String,
                      completion: @escaping (Bool, Error?) -> ()) {
        localBlobStore.store(blobIdentifier,
                             contentsOf: url,
                             filename: filename,
                             mimeType: mimeType,
                             completion: storeDataCompletionHandler(for: blobIdentifier,
                                                                    clientCompletion: completion))
    }
    
    public func fetchData(for blobIdentifier: String) -> Data? {
        guard let data = localBlobStore.fetchData(for: blobIdentifier) else {
            return remoteBlobStore.fetchData(for: blobIdentifier)
        }
        return data
    }
    
    public func fetchData(for blobIdentifier: String,
                          completion: @escaping (Data?, Error?) -> ()) {
        guard let data = fetchData(for: blobIdentifier) else {
            remoteBlobStore.fetchData(for: blobIdentifier, completion: completion)
            return
        }
        completion(data, nil)
    }
    
    public func fetchURL(for blobIdentifier: String) -> URL? {
        guard let url = localBlobStore.fetchURL(for: blobIdentifier) else {
            return remoteBlobStore.fetchURL(for: blobIdentifier)
        }
        return url
    }
    
    public func fetchURL(for blobIdentifier: String,
                  completion: @escaping (URL?, Error?) -> ()) {
        guard let url = fetchURL(for: blobIdentifier) else {
            remoteBlobStore.fetchURL(for: blobIdentifier, completion: completion)
            return
        }
        completion(url, nil)
    }
    
    public func metadata(for blobIdentifier: String) -> BlobMetadata? {
        guard let metadata = localBlobStore.metadata(for: blobIdentifier) else {
            return remoteBlobStore.metadata(for: blobIdentifier)
        }
        return metadata
    }

    public func metadata(for blobIdentifier: String,
                         completion: @escaping (BlobMetadata?, Error?) -> ()) {
        guard let metadata = localBlobStore.metadata(for: blobIdentifier) else {
            remoteBlobStore.metadata(for: blobIdentifier, completion: completion)
            return
        }
        completion(metadata, nil)
    }
    
    public func delete(_ blobIdentifier: String) throws {
        for blobStore in [localBlobStore, remoteBlobStore] as [BlobStore] {
            try blobStore.delete(blobIdentifier)
        }
    }
    
    public func shutDown(immediately: Bool) {
        for blobStore in [localBlobStore, remoteBlobStore] as [BlobStore] {
            blobStore.shutDown(immediately: immediately)
        }
    }

    // MARK: - Private utilities
    
    private func uploadAllLocalBlobs() {
        for blobIdentifier in localBlobStore.allBlobIdentifiers {
            uploadLocalBlobToRemote(blobIdentifier: blobIdentifier, completion: nil)
        }
    }
    
    private func uploadLocalBlobToRemote(blobIdentifier: String,
                                         completion: ((Bool, Error?) -> ())?) {
        guard !blobsQueuedForUpload.contains(blobIdentifier) else {
            return
        }
        
        NSLog("Blob store is queuing %@ for transfer to remote store", blobIdentifier)
        
        blobsQueuedForUpload.insert(blobIdentifier)
        
        let sourceURL = localBlobStore.fetchURL(for: blobIdentifier)!
        let cachedURL = remoteBlobStore.localCacheBlobStore.nominalFileURL(for: blobIdentifier)
        let metadata = localBlobStore.metadata(for: blobIdentifier)!
        
        remoteBlobStore.store(blobIdentifier,
                              contentsOf: sourceURL,
                              filename: metadata.filename,
                              mimeType: metadata.mimeType)
        {
            (success, error) in

            defer {
                self.blobsQueuedForUpload.remove(blobIdentifier)
            }

            guard success else {
                NotificationCenter.default.post(name: SmartBlobStore.kRemoteUploadFailedNotificationName,
                                                object: self,
                                                userInfo: [SmartBlobStore.kErrorKey : error ?? NSError()])
                completion?(false, error)
                return
            }
            
            // Shift the locally-stored payload from the local to the remote directory so that it will be immediately available to the cache.
            do {
                try FileManager.default.moveItem(at: sourceURL, to: cachedURL)
                self.remoteBlobStore.touchLastAccessDate(for: blobIdentifier)
                completion?(true, nil)
            }
            catch {
                NSLog("Blob store failed to move payload for %@ following upload: %@", blobIdentifier, String(describing: error))
                completion?(false, error)
            }
        }
    }
    
    private func storeDataCompletionHandler(for blobIdentifier: String,
                                            clientCompletion: @escaping (Bool, Error?) -> ())
        -> (Bool, Error?) -> () {
            return { (success, error) in
                guard success else {
                    clientCompletion(false, error)
                    return
                }
                
                if self.completesImmediatelyAfterLocalStore {
                    self.uploadLocalBlobToRemote(blobIdentifier: blobIdentifier,
                                                 completion: nil)
                    clientCompletion(true, nil)
                }
                else {
                    self.uploadLocalBlobToRemote(blobIdentifier: blobIdentifier,
                                                 completion: clientCompletion)
                }
            }
    }
}
