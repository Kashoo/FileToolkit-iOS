//
//  RemoteCachingBlobStoreTests.swift
//  ShoeboxTests
//
//  Created by Ben Kennedy on 2018-02-07.
//  Copyright © 2018 Kashoo Cloud Accounting Inc. All rights reserved.
//

import XCTest
import Alamofire
import Mockingjay
@testable import BlobStore

class RemoteCachingBlobStoreTests: XCTestCase {
    
    var blobStore: RemoteCachingBlobStore!
    
    override func setUp() {
        super.setUp()
        blobStore = RemoteCachingBlobStore(sessionManager: SessionManager(),
                                           remoteStoreBaseURL: URL(string: "http://blobstore.example.com")!,
                                           cacheDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("blob.test.remote"),
                                           cachePruningInterval: 0)
        
        // Stub all remote network requests with a success response.
        stub(everything, http(200, headers: [:], download: nil))
    }
    
    override func tearDown() {
        blobStore.shutDown(immediately: true)
        try! FileManager.default.removeItem(at: blobStore.localCacheBlobStore.storeDirectoryURL)
        super.tearDown()
    }
    
    // MARK: -
    
    // MARK: Cache pruning is tested in SmartBlobStoreTests; see there.
    
    func testLastAccessDate() {
        let blobIdent = "test1"

        XCTAssertNil(blobStore.metadata(for: blobIdent), "The blob should not exist yet.")

        storeTestBlobInCache(blobIdent)
        XCTAssertNotNil(blobStore.metadata(for: blobIdent), "The blob should now exist.")
        XCTAssertNil(blobStore.lastAccessDate(for: blobIdent), "The blob should not have a last-access date assigned.")

        blobStore.touchLastAccessDate(for: blobIdent)
        let date = blobStore.lastAccessDate(for: blobIdent)
        XCTAssertEqual(date!.timeIntervalSinceNow, 0, accuracy: 0.1, "The blob's last-access date should be more or less equal to right now.")
    }

    /// The method under test, `metadata(fromHeaders:)`, is actually implemented by RemoteBlobStore (our superclass).
    /// However, the latter class has no other tests yet, so this is a decent place to exercise it for now.
    ///
    func testMetadataFromHeaders() {
        let headers = [
            "File-Length" : "967217",
            "Content-Disposition" : "form-data; filename=\"oink oink.jpg\"; name=\"file\"",
            "Content-Type" : "image/jpeg",
            ]
        
        let metadata = RemoteBlobStore.metadata(fromHeaders: headers)
        XCTAssertEqual(metadata!.size, 967217)
        XCTAssertEqual(metadata!.filename, "oink oink.jpg")
        XCTAssertEqual(metadata!.mimeType, "image/jpeg")
    }

    // MARK: -
    
    func storeTestBlobInCache(_ blobIdentifier: String) {
        let expectation = self.expectation(description: "Store test data for \"\(blobIdentifier)\"")
        blobStore.localCacheBlobStore.store(blobIdentifier,
                                            data: Data(count: 1024),
                                            filename: "anonymous",
                                            mimeType: "application/x-test-data")
        { (success, error) in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

}
