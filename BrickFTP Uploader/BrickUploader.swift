//
//  BrickUploader.swift
//  Kashoo
//
//  Created by Ben Kennedy on 2018-03-13.
//  Copyright © 2018 Kashoo Cloud Accounting Inc. All rights reserved.
//

import AFNetworking

class BrickUploader {
    private var networkAgent: NetworkAgent
    private var brickAPIKey: String
    private var brickBaseURL: URL
    private let queue = OperationQueue()
    private var abortion = false

    /// A callback for monitoring upload progress (optional).
    ///
    /// - parameter completed: The number of bytes uploaded so far.
    /// - parameter ofTotal: The total number of bytes to upload.
    ///
    var progressHandler: ((_ completed: Int, _ ofTotal: Int) -> Void)?
    
    /// - parameter agent: A NetworkAgent to use for networking operations.
    /// - parameter baseURL: The base URL for the remote BrickFTP server.
    /// - parameter apiKey: The BrickFTP API key.
    ///
    init(with agent: NetworkAgent,
         baseURL: String,
         apiKey: String) {
        networkAgent = agent
        brickBaseURL = URL(string: baseURL + "/api/rest/v1/files")!
        brickAPIKey = apiKey
    }
    
    /// Upload a file to a BrickFTP server.
    ///
    /// - parameter url: A local file URL containing the data to upload.
    /// - parameter pathComponents: An array of path components relative to the BrickFTP repository in which to store the file (last of which is the target filename).
    /// - parameter completion: A handler to be called on completion.
    /// - parameter completed: `true` if the file was entirely uploaded; `false` if error or deliberately aborted.
    /// - parameter error: An error that caused upload to fail. In case of success or abortion, will be `nil`.
    ///
    func upload(file url: URL,
                to pathComponents: [String],
                completion: @escaping (_ completed: Bool, _ error: Error?) -> Void) {
        do {
            let data = try Data.init(contentsOf: url,
                                     options: [.mappedIfSafe])
            upload(data: data,
                   to: pathComponents,
                   completion: completion)
        } catch {
            completion(false, error) ; return
        }
    }
    
    /// Upload data to file on a BrickFTP server.
    ///
    /// - parameter data: The data to upload.
    /// - parameter pathComponents: An array of path components relative to the BrickFTP repository in which to store the file (last of which is the target filename).
    /// - parameter completion: A handler to be called on completion.
    /// - parameter completed: `true` if the file was entirely uploaded; `false` if error or deliberately aborted.
    /// - parameter error: An error that caused upload to fail. In case of success or abortion, will be `nil`.
    ///
    func upload(data: Data,
                to pathComponents: [String],
                completion: @escaping (_ completed: Bool, _ error: Error?) -> Void) {
        var brickRequestURL = brickBaseURL
        for component in pathComponents {
            brickRequestURL.appendPathComponent(component)
        }
        
        let totalLength = data.count
        var currentUpload: BrickUpload?
        var nextOffset = 0
        
        abortion = false
        self.progressHandler?(0, totalLength)
        
        func continueUpload() {
            guard !abortion else {
                completion(false, nil)
                return
            }
            
            self.requestUpload(forNext: currentUpload,
                               to: brickRequestURL) { result in
                switch result {
                case let .success(upload):
                    let length = min(upload.partsize, totalLength - nextOffset)
                    self.performUpload(for: upload,
                                       data: data,
                                       range: nextOffset ..< (nextOffset + length))
                    { result in
                        switch result {
                        case let .bytesSent(upload, range):
                            currentUpload = upload
                            nextOffset = range.upperBound

                            self.progressHandler?(nextOffset, totalLength)

                            if nextOffset < totalLength - 1 {
                                continueUpload()
                            } else {
                                self.completeUpload(for: upload, to: brickRequestURL) { error in
                                    completion(error == nil, self.errorIfNotCancelled(error))
                                }
                            }

                        case let .error(error):
                            completion(false, self.errorIfNotCancelled(error))
                        }
                    }

                case let .error(error):
                    completion(false, self.errorIfNotCancelled(error))
                }
            }
        }

        continueUpload()
    }
    
    /// Abort an upload in progress.
    ///
    func abort() {
        KashooActivityLog.shared().logString("Brick upload aborted.", toConsole: true)
        abortion = true
        queue.cancelAllOperations()
    }
    
    // MARK: - Networking calls
    
    enum RequestUploadResult {
        case success(BrickUpload)
        case error(Error)
    }
    
    /// https://developers.brickftp.com/#starting-a-new-upload
    /// https://developers.brickftp.com/#requesting-additional-upload-urls
    ///
    private func requestUpload(forNext upload: BrickUpload?,
                               to brickURL: URL,
                               completion: @escaping (RequestUploadResult) -> Void) {
        let body: [String: Codable]
        
        if let upload = upload {
            body = [
                "action": "put",
                "ref": upload.ref,
                "part": upload.part_number + 1,
            ]
        } else {
            body = ["action": "put"]
        }
        
        jsonPostOperation(title: "Brick request upload URL",
                          url: brickURL,
                          body: body) { (data, error) in
            guard error == nil else {
                completion(.error(error!))
                return
            }
            do {
                let newUpload = try JSONDecoder().decode(BrickUpload.self, from: data!)
                completion(.success(newUpload))
            } catch {
                completion(.error(error))
            }
        }
    }

    enum PerformUploadResult {
        case bytesSent(BrickUpload, Range<Data.Index>)
        case error(Error)
    }

    /// https://developers.brickftp.com/#uploading-the-file-or-file-parts
    ///
    private func performUpload(for upload: BrickUpload,
                               data: Data,
                               range: Range<Data.Index>,
                               completion: @escaping (PerformUploadResult) -> Void) {
        do {
            guard let url = URL(string: upload.upload_uri) else {
                throw NSError()
            }
            var request = URLRequest(url: url)
            request.httpMethod = upload.http_method
            request.allHTTPHeaderFields = upload.headers
            request.httpBody = data.subdata(in: range)
            
            let operation = AFHTTPRequestOperation(request: request)
            operation.setCompletionBlockWithSuccess({ (operation, object) in
                completion(.bytesSent(upload, range))
            }, failure: { (operation, error) in
                completion(.error(error))
            })
            
            KashooActivityLog.shared().logString("Brick uploading file body (offset \(range.lowerBound), length \(range.count)) to \(url.absoluteString)", toConsole: true)
            queue.addOperation(operation)
        } catch {
            completion(.error(error))
        }
    }
    
    /// https://developers.brickftp.com/#completing-an-upload
    ///
    private func completeUpload(for upload: BrickUpload,
                                to brickURL: URL,
                                completion: @escaping (_ error: Error?) -> Void) {
        jsonPostOperation(title: "Brick complete upload",
                          url: brickURL,
                          body: [
                            "action": "end",
                            "ref": upload.ref,
                            ])
        { (data, error) in
            completion(error) // Ignore data; at this point we are only concerned with a success/failure status.
        }
    }
    
    /// Conduct an HTTP POST containing a JSON body to the BrickFTP API.
    ///
    /// - parameter title: A descriptive string for logging in keeping with the convention used throughout the Kashoo app.
    /// - parameter url: The target URL for the HTTP POST.
    /// - parameter body: A dictionary to be expressed as JSON.
    /// - parameter completion: A completion callback with the server response.
    /// - parameter data: Response body if successful, or else `nil`.
    /// - parameter error: An error if something went wrong, or else `nil`.
    ///
    private func jsonPostOperation(title: String,
                                   url: URL,
                                   body: [String: Any],
                                   completion: @escaping (_ data: Data?, _ error: Error?) -> Void) {
        let headers = [
            "Authorization" : "Basic " + (brickAPIKey + ":x").data(using: .utf8)!.base64EncodedString(), // https://developers.brickftp.com/#starting-a-new-upload
            "Content-Type": "application/json",
            "Accept": "application/json",
            ].merging(networkAgent.applicationHeadersForHTTPRequest()) { (current, _) in return current }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = try! JSONSerialization.data(withJSONObject: body, options: [])
        request.timeoutInterval = TimeInterval(UserDefaults.standard.float(forKey: kNetworkConnectionTimeoutUserDefaultsKey))
        
        let operation = AFHTTPRequestOperation(request: request)
        operation.setCompletionBlockWithSuccess({ (operation, object) in
            KashooActivityLog.shared().logOperation(operation, name: title)
            completion(object as? Data, nil)
        }, failure: { (operation, error) in
            KashooActivityLog.shared().logOperation(operation, name: title)
            completion(nil, error)
        })
        
        queue.addOperation(operation)
    }    

    /// Transform a potential error to `nil` if it indicates a user-initiated cancellation.
    ///
    /// - parameter error: The error to transform, or `nil`.
    /// - returns: The original `error`, or `nil` if it represents a user-initiated cancellation.
    ///
    func errorIfNotCancelled(_ error: Error?) -> Error? {
        if let error = error as NSError?,
            (error.domain == kCFErrorDomainCFNetwork as String && error.code == Int(CFNetworkErrors.cfurlErrorCancelled.rawValue))
                || (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) {
            return nil
        } else {
            return error
        }
    }
    
    /// The BrickFTP upload object returned by calls to its API.
    /// https://developers.brickftp.com/#the-upload-object
    ///
    struct BrickUpload: Codable {
        var ref: String // Unique identifier to reference this file upload. This identifier is needed for subsequent requests to the REST API to complete the upload or request more upload URLs.
        var http_method: String // Value is PUT or POST, and is the HTTP method used when uploading the file to S3 at the upload_uri.
        var upload_uri: String // The URL where the file is uploaded to.
        var partsize: Int // Recommended size of upload. When uploading file pieces, the piece sizes are required to be between 5 MB and 5 GB (except the last part). This value provides a recommended size to upload for this part without adding another part.
        var part_number: Int // Number of this part, which is always between 1 and 10,000, and will always be 1 for the first upload URL at the beginning of uploading a new file.
        var available_parts: Int! // Number of parts available for this upload. For new file uploads this value is always 10,000, but it may be smaller for other uploads. When requesting more upload URLs from the REST API, the part numbers must be between 1 and this number.
        var headers: [String: String]? // A list of required headers and their exact values to send in the file upload. It may be empty if no headers with fixed values are required.
        var parameters: [String: String]? // A list of required parameters and their exact values to send in the file upload. If any values are in this array, it is implied that the upload request is formatted appropriately to send form data parameters. It will always be empty if the body of the request is specified to be where the file upload data goes (see send below).
        
        struct Send: Codable {
            // Possible values for these parameters:
            // `body`: this information is the body of the PUT or POST request
            // `required-header <header name>`: this information goes in the named header
            // `required-parameter <parameter name>`: this information goes in the named parameter, and implies this request is formatted appropriately to send form data parameters
            var file: String! // where to put the file data for the entire file upload
            var partdata: String! // where to put the file data for this part
            var partsize: String! // where to put the size of the upload for this file part
            var Content_Type: String! // where to put the Content-Type of the file (which can have no bearing on the file's actual type)
        }
        var send: Send! // This is an array of values to be sent in the file upload request.
        
        var path: String! // Intended destination path of the file upload. Path may change upon finalization, depending on existance of another upload to the same location and the site's overwrite setting.
        var action: String! // Value is always write or put for this action.
        var ask_about_overwrites: Bool! // If true, a file by this name already exists and will be overwritten when this upload completes if it continues.
    }
}
