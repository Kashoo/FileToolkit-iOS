//
//  BlobStore.swift
//  Shoebox
//
//  Created by Ben Kennedy on 2018-01-19. Ported from the Kashoo-iPad Blob Store suite originally created in 2013.
//  Copyright © 2018 Kashoo Cloud Accounting Inc. All rights reserved.
//

import Foundation

public struct BlobMetadata {
    var size: Int
    var filename: String
    var mimeType: String
}

public protocol BlobStore {

    /// Asynchronously store the payload for a blob.
    ///
    /// - parameters:
    ///   - blobIdentifier: A unique identifier for the blob.
    ///   - data: The data to store.
    ///   - filename: The filename associated with the blob as provided by the end user.
    ///   - mimeType: The MIME type describing the data.
    ///   - completion: A closure to be called on the main queue once the store is complete.
    ///   - success: `true` if sthe store succeeded, or `false` otherwise.
    ///   - error: An error that occurred in case of failure.
    ///
    func store(_ blobIdentifier: String,
               data: Data,
               filename: String,
               mimeType: String,
               completion: @escaping (_ success: Bool, _ error: Error?) -> ())

    /// Asynchronously store the payload for a blob.
    ///
    /// - parameters:
    ///   - blobIdentifier: A unique identifier for the blob.
    ///   - url: A URL on the local filesystem for the file containing the data to store.
    ///   - filename: The filename associated with the blob as provided by the end user.
    ///   - mimeType: The MIME type describing the data.
    ///   - completion: A closure to be called on the main queue once the store is complete.
    ///   - success: `true` if sthe store succeeded, or `false` otherwise.
    ///   - error: An error that occurred in case of failure.
    ///
    func store(_ blobIdentifier: String,
               contentsOf url: URL,
               filename: String,
               mimeType: String,
               completion: @escaping (_ success: Bool, _ error: Error?) -> ())

    /// Retrieve the payload associated with a blob, only if it is available immediately.
    ///
    /// - parameter blobIdentifier: The blob to retrieve.
    /// - returns: File data, if available. If data cannot be returned immediately or the blob does not exist, returns `nil`.
    ///
    func fetchData(for blobIdentifier: String) -> Data?

    /// Retrieve the payload associated with a blob.
    ///
    /// - parameters:
    ///   - blobIdentifier: The blob to retrieve.
    ///   - completion: A closure for handling the result. It will be called immediately if an answer is available now, or else scheduled on the main queue.
    ///   - data: File data, if available. If the blob does not exist, returns `nil`.
    ///   - error: An error, if one occurred.
    ///
    func fetchData(for blobIdentifier: String,
                   completion: @escaping (_ data: Data?, _ error: Error?) -> ())

    /// Retrieve the payload associated with a blob, only if it is available immediately.
    ///
    /// - parameter blobIdentifier: the blob to retrieve.
    /// - returns: File URL in the local filesystem, if available. If data cannot be returned immediately or the blob does not exist, returns `nil`.
    ///
    func fetchURL(for blobIdentifier: String) -> URL?

    /// Retrieve the payload associated with a blob asynchronously.
    ///
    /// - parameters:
    ///   - blobIdentifier: The blob to retrieve.
    ///   - completion: A closure for handling the result. It will be called immediately if an answer is available now, or else scheduled on the main queue.
    ///   - url: File URL in the local filesystem, if available. If the blob does not exist, returns `nil`.
    ///   - error: An error, if one occurred.
    ///
    func fetchURL(for blobIdentifier: String,
                  completion: @escaping (_ url: URL?, _ error: Error?) -> ())

    /// Retrieve metadata associated with a blob, only if it is available immediately.
    ///
    /// - parameter blobIdentifier: the blob to examine.
    /// - returns: metadata describing the blob, if available. If the blob does not exist, returns `nil`.
    ///
    func metadata(for blobIdentifier: String) -> BlobMetadata?

    /// Retrieve metadata associated with a blob asynchronously.
    ///
    /// - parameters:
    ///   - blobIdentifier: The blob to examine.
    ///   - completion: A closure for handling the result. It will be called immediately if an answer is available now, or else scheduled on the main queue.
    ///   - metadata: metadata describing the blob, if available. If the blob does not exist, returns `nil`.
    ///   - error: An error, if one occurred.
    ///
    func metadata(for blobIdentifier: String,
                  completion: @escaping (_ metadata: BlobMetadata?, _ error: Error?) -> ())

    /// Remove the specified blob from the store. It will be deleted immediately if it exists.
    ///
    /// - parameter blobIdentifier: the blob to delete.
    /// - throws: The underlying error if something went wrong during the deletion.
    ///
    func delete(_ blobIdentifier: String) throws
    
    /// Terminate use of the store by shutting down any background processes and freeing resources.
    ///
    /// - parameter immediately: `true` if all processes must halt forcefully; `false` if pending operations may be allowed to complete.
    ///
    func shutDown(immediately: Bool)
}
