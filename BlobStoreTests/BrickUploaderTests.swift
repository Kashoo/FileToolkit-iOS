//
//  BrickUploaderTests.swift
//  KashooLogicTests
//
//  Created by Ben Kennedy on 2018-03-15.
//  Copyright © 2018 Kashoo Cloud Accounting Inc. All rights reserved.
//

import XCTest
import OHHTTPStubs
import Alamofire
@testable import BlobStore

class BrickUploaderTests: XCTestCase {
    var uploader: BrickUploader!
    var completionExpectation: XCTestExpectation!
    
    var targetFileURL: URL?
    var targetFileHandle: FileHandle?
    var uploadRequestExpectation: XCTestExpectation!
    var uploadPutDataExpectation: XCTestExpectation!
    var completeRequestExpectation: XCTestExpectation!

    /// Chunk size that the mock server will demand of the client when uploading file data.
    let fileUploadPartSize = 10_240 // 10 KB chunks for the purposes of test.

    override func setUp() {
        super.setUp()

        // Instantiate an uploader to be exercised by each test.
        uploader = BrickUploader(with: SessionManager(),
                                 baseURL: "http://example.com",
                                 apiKey: "abc123")

        completionExpectation = expectation(description: "Uploader client completion callback")

        // Loosely simulate a BrickFTP server.
        OHHTTPStubs.stubRequests(passingTest: { (_) -> Bool in return true })
        { (request) -> OHHTTPStubsResponse in
            let requestBody = (request as NSURLRequest).ohhttpStubs_HTTPBody() // https://github.com/AliSoftware/OHHTTPStubs/wiki/Testing-for-the-request-body-in-your-stubs

            switch request.url!.absoluteString {
            case "http://example.com/api/rest/v1/files/foo/bar":
                return self.responseForBrickEndpoint(body: requestBody)

            case "http://example.com/upload":
                return self.responseForUploadEndpoint(body: requestBody)
                
            default:
                return OHHTTPStubsResponse(jsonObject: ["error" : "failure or test misconfiguration"], statusCode: 400, headers: nil)
            }
        }

        // Establish some expectations that will be fulfilled by our Brick API mocks.
        uploadRequestExpectation = expectation(description: "Brick upload part REST API call")
        uploadPutDataExpectation = expectation(description: "File storage HTTP PUT call")
        completeRequestExpectation = expectation(description: "Brick upload finished REST API call")
    }
    
    private func responseForBrickEndpoint(body: Data?) -> OHHTTPStubsResponse {
        do {
            var response: [String: Any]?
            
            if let data = body,
                let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                let action = dict["action"] as? String
            {
                switch action {
                case "put":
                    let part = (dict["part"] as? Int) ?? 1
                    response = [
                        "ref": (dict["ref"] as? String) ?? "abc123def",
                        "part_number": part,
                        "partsize": fileUploadPartSize,
                        "upload_uri": "http://example.com/upload",
                        "http_method": "PUT",
                    ]
                    if part == 1 {
                        targetFileURL = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("BrickUploadTest.data")
                        XCTAssertNotNil(targetFileURL, "We should have been able to establish a local file for storing the payload.")
                        XCTAssertNil(targetFileHandle, "File handle should not yet be open at the start of the upload.")
                        FileManager.default.createFile(atPath: targetFileURL!.path, contents: nil, attributes: nil)
                        targetFileHandle = FileHandle(forWritingAtPath: targetFileURL!.path)!
                        XCTAssertNotNil(targetFileHandle, "We should have been able to open a local file for writing.")
                    }
                    uploadRequestExpectation.fulfill()

                case "end":
                    XCTAssertNotNil(targetFileHandle, "File handle should be open; was an upload request call missed before sending data?")
                    targetFileHandle!.closeFile()
                    completeRequestExpectation.fulfill()
                    
                default: break
                }
            }
            
            return OHHTTPStubsResponse(jsonObject: response ?? [:], statusCode: 200, headers: nil)
            
        } catch {
            return OHHTTPStubsResponse(error: error)
        }
    }
    
    private func responseForUploadEndpoint(body: Data?) -> OHHTTPStubsResponse {
        XCTAssertNotNil(targetFileHandle, "File handle should be open; was an upload request call missed before sending data?")
        guard let data = body else {
            XCTFail("No data was provided in the upload body.")
            return OHHTTPStubsResponse(data: Data(), statusCode: 400, headers: nil)
        }
        
        targetFileHandle!.seekToEndOfFile()
        targetFileHandle!.write(data)

        uploadPutDataExpectation.fulfill()
        
        return OHHTTPStubsResponse(data: Data(), statusCode: 200, headers: nil)
    }
    
    override func tearDown() {
        OHHTTPStubs.removeAllStubs()
        
        if let fileHandle = targetFileHandle {
            fileHandle.closeFile()
        }
        if let url = targetFileURL,
            FileManager.default.fileExists(atPath: url.path) {
            try! FileManager.default.removeItem(at: url)
        }
        
        super.tearDown()
    }
    
    func testUploadFile() {
        // Procure a local file URL.
        let bundle = Bundle(for: type(of: self))
        let fileURL = bundle.url(forResource: "Info.plist", withExtension: nil)!
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let fileData = try! Data(contentsOf: fileURL)

        let totalParts = Int(ceil(Double(fileData.count) / Double(fileUploadPartSize)))
        uploadRequestExpectation!.expectedFulfillmentCount = totalParts
        uploadPutDataExpectation!.expectedFulfillmentCount = totalParts

        uploader.upload(file: fileURL, to: ["foo", "bar"]) { completed, error in
            XCTAssertTrue(completed, "Uploader should have indicated successful completion.")
            XCTAssertNil(error, "Uploader should have finished with no error.")
            self.completionExpectation.fulfill()
        }
        waitForExpectations(timeout: 3.0)
        
        // Verify that we stored what we expected to.
        let storedData = try! Data(contentsOf: targetFileURL!)
        XCTAssertEqual(storedData, fileData, "The data persisted to the file store should be equal to what we uploaded.")
    }

    func testUploadData() {
        // Generate some random data of reasonable size.
        var data = Data(count: 1024 * 1024)
        let count = data.count
        data.withUnsafeMutableBytes { buffer -> Void in
            XCTAssertEqual(SecRandomCopyBytes(kSecRandomDefault, count, buffer), noErr)
        }
        
        let totalParts = Int(ceil(Double(data.count) / Double(fileUploadPartSize)))
        uploadRequestExpectation!.expectedFulfillmentCount = totalParts
        uploadPutDataExpectation!.expectedFulfillmentCount = totalParts
        
        uploader.upload(data: data, to: ["foo", "bar"]) { completed, error in
            XCTAssertTrue(completed, "Uploader should have indicated successful completion.")
            XCTAssertNil(error, "Uploader should have finished with no error.")
            self.completionExpectation.fulfill()
        }
        waitForExpectations(timeout: 3.0)
        
        // Verify that we stored what we expected to.
        let storedData = try! Data(contentsOf: targetFileURL!)
        XCTAssertEqual(storedData, data, "The data persisted to the file store should be equal to what we uploaded.")
    }

    func testAbortUpload() {
        // We will issue an immediate abortion after starting, so we expect NOT to fulfill any of the API-based expectations.
//        uploadRequestExpectation.isInverted = true // Note: under AFNetworking this condition was valid. Apparently the request's life cycle is scheduled differently under Alamofire.
        uploadPutDataExpectation.isInverted = true
        completeRequestExpectation.isInverted = true

        uploader.upload(data: Data(count: 1024 * 1024), to: ["foo", "bar"]) { completed, error in
            XCTAssertFalse(completed, "Uploader should have indicated non-completion due to the abortion.")
            XCTAssertNil(error, "Uploader should have finished with no error.")
            self.completionExpectation.fulfill()
        }
        uploader.abort()
        
        waitForExpectations(timeout: 1.0)
    }

    func testServerError() {
        // We're going to simulate a failed server response by specifying an upload path that our HTTP mock doesn't match.
        // Consequently we expect NOT to fulfill any of the API-based expectations.
        uploadRequestExpectation.isInverted = true
        uploadPutDataExpectation.isInverted = true
        completeRequestExpectation.isInverted = true
        
        uploader.upload(data: Data(), to: ["bogus", "directory", "path"]) { completed, error in
            XCTAssertFalse(completed, "Uploader should have indicated non-completion due to the bad path.")
            XCTAssertNotNil(error, "Uploader should have finished with an error since we specified a bad path.")
            self.completionExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
}
