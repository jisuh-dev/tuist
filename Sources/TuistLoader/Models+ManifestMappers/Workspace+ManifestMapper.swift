import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.Workspace {
    /// Maps a ProjectDescription.Workspace instance into a XcodeGraph.Workspace model.
    /// - Parameters:
    ///   - manifest: Manifest representation of workspace.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.Workspace,
        path: AbsolutePath,
        generatorPaths: GeneratorPaths,
        manifestLoader: ManifestLoading
    ) async throws -> XcodeGraph.Workspace {
        func globProjects(_ path: Path) throws -> [AbsolutePath] {
            let resolvedPath = try generatorPaths.resolve(path: path)
            let projects = FileHandler.shared.glob(AbsolutePath.root, glob: String(resolvedPath.pathString.dropFirst()))
                .filter(FileHandler.shared.isFolder)
                .filter { $0.basename != Constants.tuistDirectoryName && !$0.pathString.contains(".build/checkouts") }
                .filter {
                    manifestLoader.manifests(at: $0).contains(where: { $0 == .package || $0 == .project })
                }

            if projects.isEmpty {
                // FIXME: This should be done in a linter.
                // Before we can do that we have to change the linters to run with the TuistCore models and not the
                // ProjectDescription ones.
                logger.warning("No projects found at: \(path.pathString)")
            }

            return Array(projects)
        }

        let additionalFiles = try await manifest.additionalFiles
            .concurrentFlatMap {
                try await XcodeGraph.FileElement.from(manifest: $0, generatorPaths: generatorPaths)
            }

        let schemes = try await manifest.schemes.concurrentMap { try await XcodeGraph.Scheme.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }

        let generationOptions: GenerationOptions = try .from(manifest: manifest.generationOptions, generatorPaths: generatorPaths)

        let ideTemplateMacros = try manifest.fileHeaderTemplate
            .map { try IDETemplateMacros.from(manifest: $0, generatorPaths: generatorPaths) }

        return XcodeGraph.Workspace(
            path: path,
            xcWorkspacePath: path.appending(component: "\(manifest.name).xcworkspace"),
            name: manifest.name,
            projects: try manifest.projects.flatMap(globProjects),
            schemes: schemes,
            generationOptions: generationOptions,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles
        )
    }
}
