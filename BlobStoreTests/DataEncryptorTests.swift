//
//  DataEncryptorTests.swift
//  BlobStoreTests
//
//  Created by Ben Kennedy on 2018-04-11.
//  Copyright © 2018 Kashoo Systems Inc. All rights reserved.
//

import XCTest
@testable import BlobStore

class DataEncryptorTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testDataEncryptor() {
        let bundle = Bundle(for: type(of: self))
        let encryptor = DataEncryptor(x509URL: bundle.url(forResource: "encrypt_public_key.der", withExtension: nil))!
        let plaintext = try! Data(contentsOf: bundle.url(forResource: "Info.plist", withExtension: nil)!)
        let ciphertext = encryptor.encryptData(plaintext)

        XCTAssertNotNil(encryptor.encryptedSymmetricKey, "Encryptor should return an encrypted symmetric key.")
        XCTAssertGreaterThan(encryptor.encryptedSymmetricKey.count, 10, "Encrypted symmetric key should have some non-trivial size.")
        XCTAssertNotNil(ciphertext, "Encryptor should have produced a ciphertext.")
        XCTAssertGreaterThan(ciphertext!.count, 10, "Encrypted payload should have some non-trivial size.")
    }
    
    // No test for the decryptor, since it currently only exists as a shell script, which won't run in an iOS simulator.
}
