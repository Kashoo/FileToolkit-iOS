//
//  LocalBlobStoreTests.swift
//  FileToolkitTests
//
//  Copyright 2013 Kashoo Cloud Accounting Inc.
//  Copyright 2018 Kashoo Systems Inc.
//

import XCTest
@testable import FileToolkit

class LocalBlobStoreTests: XCTestCase {

    var blobStore: LocalBlobStore!
    
    var testBlobIdent = "test123"
    var testFilename = "test " + String(arc4random())
    var testMimeType = "application/x-test-data"
    var testPayload = "Imagine what you could get done with your own team of bookkeeping & tax professionals taking care of the back-office parts of your business you'd rather not focus on.".data(using: .utf8)!

    override func setUp() {
        super.setUp()
        blobStore = LocalBlobStore(storeDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("blob.test.local"))
    }
    
    override func tearDown() {
        blobStore.shutDown(immediately: true)
        try! FileManager.default.removeItem(at: blobStore.storeDirectoryURL)
        super.tearDown()
    }
    
    // MARK: - Affirmative tests
    
    func testStore() {
        var expectation: XCTestExpectation
        
        // Store from a data object.
        // (The same logic is used in the storeTestBlobAndWait() utility method, but copied verbatim here for clarity of this test.)
        expectation = self.expectation(description: "Store blob from a data object")
        blobStore.store(testBlobIdent,
                        data: testPayload,
                        filename: testFilename,
                        mimeType: testMimeType)
        { (success, error) in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        // Delete the blob (so that we can store it again).
        try! blobStore.delete(testBlobIdent)
        
        // Store from a file URL.
        expectation = self.expectation(description: "Store blob from a file URL")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.txt")
        try! testPayload.write(to: url, options: .atomic)
        blobStore.store(testBlobIdent,
                        contentsOf: url,
                        filename: testFilename,
                        mimeType: testMimeType)
        { (success, error) in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        try? FileManager.default.removeItem(at: url)
    }
    
    func testDelete() {
        XCTAssertNil(blobStore.metadata(for: testBlobIdent), "The blob should not exist yet.")
        XCTAssertNil(blobStore.fetchData(for: testBlobIdent), "The blob should not exist yet.")

        storeTestBlobAndWait()
        XCTAssertNotNil(blobStore.metadata(for: testBlobIdent), "The blob should now exist.")
        XCTAssertNotNil(blobStore.fetchData(for: testBlobIdent), "The blob should now exist.")

        XCTAssertNoThrow(try blobStore.delete(testBlobIdent), "Deletion should succeed.")
        XCTAssertNil(blobStore.metadata(for: testBlobIdent), "The blob should no longer exist.")
        XCTAssertNil(blobStore.fetchData(for: testBlobIdent), "The blob should no longer exist.")
    }
    
    func testFetchSync() {
        storeTestBlobAndWait()
        
        // Fetch as data object.
        let data = blobStore.fetchData(for: testBlobIdent)
        XCTAssertEqual(data, testPayload)
        
        // Fetch as file URL.
        let url = blobStore.fetchURL(for: testBlobIdent)
        XCTAssertEqual(try! Data(contentsOf: url!), testPayload)
        
        // Fetch metadata.
        let metadata = blobStore.metadata(for: testBlobIdent)
        XCTAssertEqual(metadata!.size, testPayload.count)
        XCTAssertEqual(metadata!.filename, testFilename)
        XCTAssertEqual(metadata!.mimeType, testMimeType)
    }
    
    func testFetchAsync() {
        storeTestBlobAndWait()
        var expectation: XCTestExpectation
        
        // Fetch as data object.
        expectation = self.expectation(description: "Fetch blob asynchronously as data")
        blobStore.fetchData(for: testBlobIdent) { (data, error) in
            XCTAssertEqual(data, self.testPayload)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        // Fetch as file URL.
        expectation = self.expectation(description: "Fetch blob asynchronously as file URL")
        blobStore.fetchURL(for: testBlobIdent) { (url, error) in
            XCTAssertEqual(try! Data(contentsOf: url!), self.testPayload)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        // Fetch metadata.
        expectation = self.expectation(description: "Fetch metadata asynchronously")
        blobStore.metadata(for: testBlobIdent) { (metadata, error) in
            XCTAssertEqual(metadata!.size, self.testPayload.count)
            XCTAssertEqual(metadata!.filename, self.testFilename)
            XCTAssertEqual(metadata!.mimeType, self.testMimeType)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }
    
    func testStoreAndFetchMultipleDistinct() {
        let numberOfBlobs = 4
        var inData = [Data]()
        var outData = [Data]()
        var ident = [String]()
        
        for i in 0 ..< numberOfBlobs {
            // Generate some distinct random data.
            var data = Data(count: 1024)
            let count = data.count
            data.withUnsafeMutableBytes { pointer -> Void in
                arc4random_buf(pointer, count)
            }
            inData.append(data)
            
            if i > 0 {
                XCTAssertNotEqual(inData[i], inData[i - 1], "Two sets of randomized input data should not be identical.")
            }
            
            ident.append(NSUUID().uuidString)
            XCTAssertNotNil(ident[i])

            testBlobIdent = ident[i]
            testPayload = inData[i]
            testFilename = "test \(i)"
            storeTestBlobAndWait()
        }

        for i in 0 ..< numberOfBlobs {
            // Verify that the prescribed original metadata were stored and retrieved.
            let metadata = blobStore.metadata(for: ident[i])!
            XCTAssertEqual(metadata.size, 1024, "The original blob size should be preserved.")
            XCTAssertEqual(metadata.filename, "test \(i)", "The prescribed original filename should be preserved.")
            XCTAssertEqual(metadata.mimeType, "application/x-test-data", "The prescribed original MIME type should be preserved.")

            // Retrieve them from the store as data blobs.
            outData.append(blobStore.fetchData(for: ident[i])!)
            XCTAssertEqual(outData[i], inData[i], "The stored and retrieved data for blob \(i) should have been the same.")
        }
    }
    
    // MARK: - Negative tests
    
    func testStoreFails() {
        // Validate that an attempt to re-store a blob under an existing identifier fails.
        var expectation: XCTestExpectation!
        storeTestBlobAndWait()

        // Store from a data object.
        expectation = self.expectation(description: "Store duplicate blob from data")
        blobStore.store(testBlobIdent,
                        data: testPayload,
                        filename: testFilename,
                        mimeType: testMimeType)
        { (success, error) in
            XCTAssertFalse(success, "An attempt to store a blob using an existing identifier should fail.")
            XCTAssertNotNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // Store from a file URL.
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.txt")
        try! testPayload.write(to: url, options: .atomic)
        expectation = self.expectation(description: "Store duplicate blob from file URL")
        blobStore.store(testBlobIdent,
                        contentsOf: url,
                        filename: testFilename,
                        mimeType: testMimeType)
        { (success, error) in
            XCTAssertFalse(success, "An attempt to store a blob using an existing identifier should fail.")
            XCTAssertNotNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        try? FileManager.default.removeItem(at: url)
    }
    
    func testDeleteFails() {
        XCTAssertThrowsError(try blobStore.delete(testBlobIdent), "An attempt to delete a non-existent blob should throw an error.")
    }

    func testFetchSyncFails() {
        // Fetch as data object.
        XCTAssertNil(blobStore.fetchData(for: testBlobIdent), "An attempt to fetch a non-existent blob should return nil data.")
        
        // Fetch as file URL.
        XCTAssertNil(blobStore.fetchURL(for: testBlobIdent), "An attempt to fetch a non-existent blob should return a nil URL.")
        
        // Fetch metadata.
        XCTAssertNil(blobStore.metadata(for: testBlobIdent), "An attempt to fetch a non-existent blob should return nil metadata.")
    }
    
    func testFetchAsyncFails() {
        var expectation: XCTestExpectation
        
        // Fetch as data object.
        expectation = self.expectation(description: "Fetch non-existent blob asynchronously as data")
        blobStore.fetchData(for: testBlobIdent) { (data, error) in
            XCTAssertNil(data, "An attempt to fetch a non-existent blob should return nil data.")
            XCTAssertNil(error, "An attempt to fetch a non-existent blob should not return an error.")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        // Fetch as file URL.
        expectation = self.expectation(description: "Fetch non-existent blob asynchronously as file URL")
        blobStore.fetchURL(for: testBlobIdent) { (url, error) in
            XCTAssertNil(url, "An attempt to fetch a non-existent blob should return a nil URL.")
            XCTAssertNil(error, "An attempt to fetch a non-existent blob should not return an error.")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        // Fetch metadata.
        expectation = self.expectation(description: "Fetch metadata for non-existent blob asynchronously")
        blobStore.metadata(for: testBlobIdent) { (metadata, error) in
            XCTAssertNil(metadata, "An attempt to fetch a non-existent blob should return nil metadata.")
            XCTAssertNil(error, "An attempt to fetch a non-existent blob should not return an error.")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }
    
    // MARK: -
    
    func storeTestBlobAndWait() {
        let expectation = self.expectation(description: "Store test data \"\(testFilename)\"")
        blobStore.store(testBlobIdent,
                        data: testPayload,
                        filename: testFilename,
                        mimeType: testMimeType)
        { (success, error) in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }
    
}
