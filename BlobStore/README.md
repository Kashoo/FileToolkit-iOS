# BlobStore

BlobStore provides abstract and concrete interfaces for the upload, download, and caching of arbitrary and named raw data with a remote file server.

## Features:

- synchronous and asynchronous API
- local caching, with automatic cache management
- preservation of original filename and MIME type

See [BlobStore.swift](./BlobStore/BlobStore.swift) protocol for overview.

## The concrete implementations

- [LocalBlobStore](./LocalBlobStore.swift): deals in local disk-backed files.
- [RemoteBlobStore](./RemoteBlobStore.swift): deals in remote network-backed resources.
- [RemoteCachingBlobStore](./RemoteCachingBlobStore.swift): deals in network-backed resources that are also cached locally upon download. (A subclass of RemoteBlobStore, employing LocalBlobStore.)
- [SmartBlobStore](./SmartBlobStore.swift): deals in network-backed resources that are cached locally on both download and upload, thus facilitating bidirectional offline operation. (Employs RemoteCachingBlobStore and LocalBlobStore.)

### Fetching as Data vs. URL

The API for blob retrieval provides both `Data` and local file `URL`-based methods. Depending on the use case one might be more suitable. Also, depending on the concrete implementation, behaviour might be different—for example, RemoteBlobstore will always return a nil `URL` since it creates no persistent resource.
