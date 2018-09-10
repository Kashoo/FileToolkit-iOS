# BrickUploader

BrickUploader coordinates the upload of data to [BrickFTP](http://www.brickftp.com) using its [REST API](https://developers.brickftp.com/#file-uploading).

## Usage

```swift
let uploader = BrickUploader(with: SessionManager(),
                             baseURL: "https://example.brickftp.com",
                             apiKey: "1234567890")

uploader.progressHandler = { (completed, ofTotal) in
    print("Uploaded \(completed) of \(ofTotal) bytes")
}

let url = URL(fileURLWithPath: "/tmp/source.txt")
let path = ["dir1", "dir2", "destination.txt"]

uploader.upload(file: url, to: path) { completed, error in
    guard error == nil else {
        print("Uh oh: \(error.localizedDescription)")
    }
}
```
