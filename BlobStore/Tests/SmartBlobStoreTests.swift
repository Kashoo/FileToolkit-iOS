//
//  SmartBlobStoreTests.swift
//  FileToolkitTests
//
//  Copyright 2013 Kashoo Cloud Accounting Inc.
//  Copyright 2018 Kashoo Systems Inc.
//

import XCTest
import Alamofire
@testable import FileToolkit

class SmartBlobStoreTests: XCTestCase {
    
    var blobStore: SmartBlobStore!
    
    let testBlobSize = 1024
    
    override func setUp() {
        super.setUp()
        blobStore = SmartBlobStore(sessionManager: SessionManager(),
                                   localQueueDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("blob.test.local"),
                                   remoteCacheDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("blob.test.remote"),
                                   remoteStoreBaseURL: URL(string: "http://blobstore.example.com")!,
                                   cachePruningInterval: 0) // disable automatic pruning so that we can exercise it manually.

        // Disable asynchronous remote storage so that we can properly control the life cycle of operations for the tests.
        blobStore.completesImmediatelyAfterLocalStore = false
    }
    
    override func tearDown() {
        blobStore.shutDown(immediately: true)
        try! FileManager.default.removeItem(at: blobStore.localBlobStore.storeDirectoryURL)
        try! FileManager.default.removeItem(at: blobStore.remoteBlobStore.localCacheBlobStore.storeDirectoryURL)
        super.tearDown()
    }
    
    // MARK: -
    
    func testStore() {
        let blobIdent = "test"
        XCTAssertNil(blobStore.fetchData(for: blobIdent), "The blob should not exist anywhere yet.")

        storeTestBlob(blobIdent)
        XCTAssertNotNil(blobStore.fetchData(for: blobIdent), "The blob should be retrievable from the smart store.")
        XCTAssertNil(blobStore.localBlobStore.fetchData(for: blobIdent), "Despite having been stored, the blob should be absent from the local durable store since it has been uploaded to the remote.")
        XCTAssertNotNil(blobStore.remoteBlobStore.fetchData(for: blobIdent), "The blob should be retrievable from the remote store via its cache.")
    }
    
    /// Cache pruning is implemented and managed by RemoteCachingBlobStore. However, the cache is only filled after a remote download, or a store by SmartBlobStore.
    /// Therefore, instead of mocking out a bunch of network-hosted blobs in RemoteCachingBlobStore, we'll test the cache here instead since it's also fundamental to SmartBlobStore's operation.
    ///
    func testRemoteCachePruning() {
        XCTAssertEqual(remoteCacheSize(), 0, "The remote cache should be empty to start.")

        // Store a bunch of blobs, and validate that they fill up the remote cache.
        for i in 0..<10 {
            storeTestBlob("test\(i)")
        }
        XCTAssertEqual(remoteCacheSize(), testBlobSize * 10, "Having stored several blobs, the cache should be appropriately full.")

        // Clamp the cache size so that it will only accommodate a few blobs, and validate that it prunes.
        blobStore.remoteBlobStore.maximumCacheSize = testBlobSize * 5
        blobStore.remoteBlobStore.pruneCache()
        XCTAssertEqual(remoteCacheSize(), testBlobSize * 5, "Having set a cache limit and then pruned, the cache should be appropriately constrained.")
        
        // Validate that the pruning was performed in favour of the most recently added blobs.
        var remainingBlobs = blobStore.remoteBlobStore.localCacheBlobStore.allBlobIdentifiers
        var expectedBlobs: Set<String> = ["test5", "test6", "test7", "test8", "test9"]
        XCTAssertEqual(remainingBlobs, expectedBlobs, "After pruning the cache should contain only the most recently used blobs.")
        
        // Make a load against three blobs, then reduce the cache size further, and validate that it still favours the most recent.
        XCTAssertNotNil(blobStore.fetchURL(for: "test6"))
        XCTAssertNotNil(blobStore.fetchURL(for: "test7"))
        XCTAssertNotNil(blobStore.fetchData(for: "test8"))
        blobStore.remoteBlobStore.maximumCacheSize = Int(Double(testBlobSize) * 2.5)
        blobStore.remoteBlobStore.pruneCache()
        
        remainingBlobs = blobStore.remoteBlobStore.localCacheBlobStore.allBlobIdentifiers
        expectedBlobs = ["test7", "test8"]
        XCTAssertEqual(remainingBlobs, expectedBlobs, "After further constraint and pruning the cache should contain only the most recently fetched blobs.")
    }
    
    // MARK: -

    func storeTestBlob(_ blobIdentifier: String) {
        // Store some nominal data with which we can test retrieval.
        let expectation = self.expectation(description: "Store test data for \"\(blobIdentifier)\"")
        blobStore.store(blobIdentifier,
                        data: Data(count: testBlobSize),
                        filename: "anonymous",
                        mimeType: "application/x-test-data")
        { (success, error) in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func remoteCacheSize() -> Int {
        var totalCacheSize: Int = 0
        for url in try! FileManager.default.contentsOfDirectory(at: blobStore.remoteBlobStore.localCacheBlobStore.storeDirectoryURL,
                                                                includingPropertiesForKeys: [.fileAllocatedSizeKey],
                                                                options: [])
        {
            let resourceValues = try! url.resourceValues(forKeys: [.fileSizeKey])
            totalCacheSize += resourceValues.fileSize!
        }
        return totalCacheSize
    }
}

