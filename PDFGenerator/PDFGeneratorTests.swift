//
//  PDFGeneratorTests.swift
//  FileToolkitTests
//
//  Created by Ben Kennedy on 2018-04-17.
//  Copyright © 2018 Kashoo Systems Inc. All rights reserved.
//

import XCTest
import CoreGraphics
@testable import FileToolkit

class PDFGeneratorTests: XCTestCase {
    
    let html = """
<style>
    body {
        background: blue;
        font-family: sans-serif;
    }
</style>
<body>
    <h1>Hello world!</h1>
    <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aenean ut aliquet massa. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Morbi at porttitor diam, ut rhoncus felis.</p>
</body>
"""

    func testGenerateImage() {
        let imageExpectation = expectation(description: "Generate PNG image representation")
        let generator = PDFGenerator()
        generator.sourceHTML = html
        generator.generateImage { image in
            XCTAssertNotNil(image, "The generator should return an image.")
            XCTAssertEqual((image!.size.width / image!.size.height), (8.5 / 11), "The image should carry dimensions of a US Letter sized document.")
            let pngData = UIImagePNGRepresentation(image!)
            XCTAssertNotNil(pngData, "The image should be representable as a PNG.")
            XCTAssertGreaterThanOrEqual(pngData!.count, 5_000, "The PNG data should be of substantive size.")
            imageExpectation.fulfill()
        }
        waitForExpectations(timeout: 3.0)
    }
    
    func testGeneratePDF() {
        let pdfExpectation = expectation(description: "Generate PDF representation")
        let generator = PDFGenerator()
        generator.sourceHTML = html
        generator.generatePDF { pdfData in
            XCTAssertNotNil(pdfData, "The generator should return PDF data.")
            XCTAssertGreaterThanOrEqual(pdfData!.count, 5_000, "The PDF data should be of substantive size.")
            let document = CGPDFDocument(CGDataProvider(data: pdfData! as NSData)!)
            XCTAssertNotNil(document, "The data should be valid re-interpretable PDF.")
            XCTAssertEqual(document!.numberOfPages, 1, "The PDF file should have one page.")
            let page = document!.page(at: 1)!
            let rect = page.getBoxRect(.mediaBox)
            XCTAssertEqual((rect.size.width / rect.size.height), (8.5 / 11), "The PDF media box should carry dimensions of a US Letter sized document.")
            pdfExpectation.fulfill()
        }
        waitForExpectations(timeout: 3.0)
    }

}
