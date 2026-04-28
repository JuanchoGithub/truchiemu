import Foundation

/// Service for safely migrating save files between directories
/// Implements copy-then-delete strategy with verification
public final class SaveMigrationService {
    
    struct MigrationProgress {
        var totalFiles: Int = 0
        var completedFiles: Int = 0
        var currentFile: String?
        var isComplete: Bool = false
        
        var progress: Double {
            totalFiles == 0 ? 0 : Double(completedFiles) / Double(totalFiles)
        }
    }
    
    enum MigrationError: Error {
        case cannotCreateDestination
        case copyFailed(underlying: Error)
        case verificationFailed
        case userCancelled
    }
    
    // MARK: - State
    private let fileManager = FileManager.default
    private var isCancelled = false
    
    // MARK: - Public API
    
    /// Migrates files from one directory to another with progress
    /// - Parameters:
    /// - source: Source directory
    /// - destination: Destination directory
    /// - progressHandler: Called periodically with progress updates
    /// - completion: Called on completion with success/failure
    func migrate(
        from source: URL,
        to destination: URL,
        progressHandler: ((MigrationProgress) -> Void)? = nil,
        completion: ((Result<Void, MigrationError>) -> Void)? = nil
    ) {
        let queue = DispatchQueue(label: "com.truchie.migration", attributes: .concurrent)
        
        queue.async { [weak self] in
            do {
                guard let self = self else {
                    completion?(.failure(.copyFailed(underlying: CancellationError())))
                    return
                }
                
                // Phase 1: Discover all files to migrate
                let files = try self.discoverFiles(at: source)
                var progress = MigrationProgress(totalFiles: files.count)
                progressHandler?(progress)
                
                // Phase 2: Copy files with progress
                for fileURL in files {
                    try self.throwIfCancelled()
                    progress.currentFile = fileURL.lastPathComponent
                    progressHandler?(progress)
                    
                    try self.copyFile(
                        from: fileURL,
                        sourceRoot: source,
                        destinationRoot: destination
                    )
                    
                    progress.completedFiles += 1
                }
                
                // Phase 3: Verification
                try self.throwIfCancelled()
                
                let verified = self.verifyContents(
                    source: source,
                    destination: destination
                )
                
                guard verified else {
                    throw MigrationError.verificationFailed
                }
                
                // Phase 4: Cleanup (only if verification passed)
                try self.removeSourceFiles(files: files, sourceRoot: source)
                
                progress.currentFile = nil
                progress.isComplete = true
                progressHandler?(progress)
                
                completion?(.success(()))
                
            } catch {
                if let migrationError = error as? MigrationError {
                    completion?(.failure(migrationError))
                } else {
                    completion?(.failure(.copyFailed(underlying: error)))
                }
            }
        }
    }
    
    func cancel() {
        isCancelled = true
    }
    
    // MARK: - Private Implementation
    
    private func discoverFiles(at source: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: source.path) else {
            return []
        }
        
        var files: [URL] = []
        
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            throw MigrationError.cannotCreateDestination
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if try resourceValues.isDirectory != true {
                files.append(fileURL)
            }
        }
        
        return files
    }
    
    private func copyFile(
        from sourceFile: URL,
        sourceRoot: URL,
        destinationRoot: URL
    ) throws {
        let relativePath = sourceFile.path.replacingOccurrences(of: sourceRoot.path, with: "")
        let destinationFile = destinationRoot.appendingPathComponent(relativePath)
        let destinationDir = destinationFile.deletingLastPathComponent()
        
        try fileManager.createDirectory(
            at: destinationDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        try fileManager.copyItem(at: sourceFile, to: destinationFile)
        
        // Preserve modification date and attributes
        var attributes = try fileManager.attributesOfItem(atPath: sourceFile.path)
        attributes.removeValue(forKey: .modificationDate) // We'll set this separately
        
        if let modDate = attributes[.modificationDate] as? Date {
            try fileManager.setAttributes(
                [.modificationDate: modDate],
                ofItemAtPath: destinationFile.path
            )
        }
    }
    
    private func verifyContents(
        source: URL,
        destination: URL
    ) -> Bool {
        guard let sourceFiles = try? fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: []
        ) else {
            return true // Source empty or doesn't exist
        }
        
        guard let destFiles = try? fileManager.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: []
        ) else {
            return false // Destination doesn't exist
        }
        
        // Basic check: same number of files
        guard sourceFiles.count == destFiles.count else {
            LoggerService.error(
                category: "Migration",
                "Verification failed: file count mismatch. Source: \(sourceFiles.count), Dest: \(destFiles.count)"
            )
            return false
        }
        
        // Size check (within small tolerance for metadata differences)
        let sourceSize = sourceFiles.compactMap {
            try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }.reduce(0, +)
        
        let destSize = destFiles.compactMap {
            try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }.reduce(0, +)
        
        let sizeDiff = abs(sourceSize - destSize)
        let sizeDiffPercent = Double(sizeDiff) / Double(max(sourceSize, 1))
        
        if sizeDiffPercent > 0.01 { // More than 1% size difference
            LoggerService.error(
                category: "Migration",
                "Verification failed: size mismatch. Diff: \(sizeDiff) bytes (\(sizeDiffPercent))"
            )
            return false
        }
        
        return true
    }
    
    private func removeSourceFiles(files: [URL], sourceRoot: URL) throws {
        // Remove individual files but keep directory structure
        for file in files {
            try fileManager.removeItem(at: file)
        }
    }
    
    private func throwIfCancelled() throws {
        if isCancelled {
            throw MigrationError.userCancelled
        }
    }
}
