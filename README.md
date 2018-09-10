#  Kashoo FileToolkit

Herein lies a varied collection of file-related utilities all variously employed in the [Kashoo](http://www.kashoo.com) iOS app.

The bulk of this code was originally written by [Ben Kennedy](https://github.com/zygoat/) on behalf (and copyright) of Kashoo Systems Inc., and is offered for general use and enrichment under the [MIT License](./LICENSE.md).

## Table of contents:

- [BlobStore](./BlobStore/) — Manages the upload, download, and caching of arbitrary data with a remote file server.
- [BrickUploader](./BrickUploader/) — Coordinates the upload of data to [BrickFTP](http://www.brickftp.com) using its REST API.
- [DataEncryptor](./DataEncryptor/) — A lightweight utility for compressing and encrypting an arbitrary payload.
- [PDFGenerator](./PDFGenerator/) — Renders an HTML document as a PDF file, and produces a PNG of its first page.

The included [xcworkspace](./FileToolkit.xcworkspace) provides unit tests for all projects. [CocoaPods](http://www.cocoapods.org) is required.
