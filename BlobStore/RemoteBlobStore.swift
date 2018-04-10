//
//  RemoteBlobStore.swift
//  Shoebox
//
//  Created by Ben Kennedy on 2018-01-19. Ported from the Kashoo-iPad Blob Store suite originally created in 2013.
//  Copyright © 2018 Kashoo Cloud Accounting Inc. All rights reserved.
//

import Alamofire

public class RemoteBlobStore: BlobStore {

    let sessionManager: SessionManager
    let baseURL: URL
    
    public init(sessionManager: SessionManager,
                baseURL: URL) {
        self.sessionManager = sessionManager
        self.baseURL = baseURL
    }

    // MARK: - BlobStore protocol

    public func store(_ blobIdentifier: String,
                      data: Data,
                      filename: String,
                      mimeType: String,
                      completion: @escaping (Bool, Error?)->()) {
        self.store(formData: { formData in
            formData.append(data,
                            withName: "file",
                            fileName: filename,
                            mimeType: mimeType)
        },
                   blobIdentifier: blobIdentifier, filename: filename, mimeType: mimeType, completion: completion)
    }
        
    public func store(_ blobIdentifier: String,
                      contentsOf url: URL,
                      filename: String,
                      mimeType: String,
                      completion: @escaping (Bool, Error?)->()) {
        self.store(formData: { formData in
            formData.append(url,
                            withName: "file",
                            fileName: filename,
                            mimeType: mimeType)
        },
                   blobIdentifier: blobIdentifier, filename: filename, mimeType: mimeType, completion: completion)
    }
        
    public func fetchData(for blobIdentifier: String) -> Data? {
        // Since this is a cacheless network service, these data will never be available immediately; the asynchronous counterpart should be used.
        return nil
    }

    public func fetchData(for blobIdentifier: String,
                          completion: @escaping (Data?, Error?) -> ()) {
        sessionManager.request(baseURL.appendingPathComponent(blobIdentifier),
                               method: .get)
            .responseData { response in
                completion(response.result.value, response.result.error)
        }
    }

    public func fetchURL(for blobIdentifier: String) -> URL? {
        preconditionFailure("We deal in network data only; use the Data-based API.")
    }

    public func fetchURL(for blobIdentifier: String,
               completion: @escaping (URL?, Error?) -> ()) {
        preconditionFailure("We deal in network data only; use the Data-based API.")
    }
    
    public func metadata(for blobIdentifier: String) -> BlobMetadata? {
        // Since this is a cacheless network service, these data will never be available immediately; the asynchronous counterpart should be used.
        return nil
    }
    
    public func metadata(for blobIdentifier: String,
                         completion: @escaping (BlobMetadata?, Error?) -> ()) {
        sessionManager.request(baseURL.appendingPathComponent(blobIdentifier),
                               method: .head)
            .responseJSON { (response) in
                guard response.result.isSuccess else {
                    completion(nil, response.error)
                    return
                }
                
                guard let headers = response.response?.allHeaderFields,
                    let metadata = RemoteBlobStore.metadata(fromHeaders: headers) else {
                        completion(nil, response.error)
                        return
                }
                
                completion(metadata, nil)
        }
    }
    
    public func delete(_ blobIdentifier: String) throws {
        preconditionFailure("Remote deletion is not implemented; \(blobIdentifier) will persist.")
    }

    public func shutDown(immediately: Bool) {
        if immediately {
            sessionManager.session.invalidateAndCancel()
        }
    }
    
    // MARK: - Internal tools
    
    private func store(formData: @escaping (MultipartFormData) -> Void,
                       blobIdentifier: String,
                       filename: String,
                       mimeType: String,
                       completion: @escaping (Bool, Error?)->()) {
        sessionManager.upload(multipartFormData: formData,
                              to: baseURL.appendingPathComponent(blobIdentifier)) { (encodingResult) in
                                switch encodingResult {
                                case .success(let upload, _, _):
                                    upload.response { response in
                                        completion(true, nil)
                                    }
                                case .failure(let encodingError):
                                    completion(false, encodingError)
                                }
        }
    }
    
    /// Create a metadata struct by parsing a dictionary of HTTP headers.
    ///
    /// - parameter headers: A dictionary of HTTP headers such as returned by an HTTP HEAD request.
    /// - returns: A corresponding metadata struct. If any of the component headers is missing, returns `nil`.
    ///
    static func metadata(fromHeaders headers: [AnyHashable : Any]) -> BlobMetadata? {
        // File-Length: 967217
        guard let sizeHeader = headers["File-Length"] as? String,
            let size = Int(sizeHeader) else {
                return nil
        }
        
        // Content-Type: image/jpeg
        guard let mimeType = headers["Content-Type"] as? String else {
            return nil
        }
        
        // Content-Disposition: form-data; filename="86387F23-878E-49A6-8D64-9B3039857CC1"; name="file"
        guard let disposition = headers["Content-Disposition"] as? String,
            let regex = try? NSRegularExpression(pattern: "filename=\"([^\"]+)\"", options: [.caseInsensitive]),
            let matchResult = regex.matches(in: disposition, options: [], range: NSRange(location: 0, length: disposition.count)).first,
            let range = Range(matchResult.range(at: 1), in: disposition) else {
                return nil
        }
        let filename = String(disposition[range])
        
        return BlobMetadata(size: size,
                            filename: filename,
                            mimeType: mimeType)
    }
}
