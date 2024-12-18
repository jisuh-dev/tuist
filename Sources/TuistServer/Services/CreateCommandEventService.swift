import Foundation
import Mockable
import OpenAPIURLSession
import TuistCore
import TuistSupport

@Mockable
public protocol CreateCommandEventServicing {
    func createCommandEvent(
        commandEvent: CommandEvent,
        projectId: String,
        serverURL: URL
    ) async throws -> ServerCommandEvent
}

enum CreateCommandEventServiceError: FatalError {
    case unknownError(Int)
    case forbidden(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The organization could not be created due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class CreateCommandEventService: CreateCommandEventServicing {
    public init() {}

    public func createCommandEvent(
        commandEvent: CommandEvent,
        projectId: String,
        serverURL: URL
    ) async throws -> ServerCommandEvent {
        let client = Client.authenticated(serverURL: serverURL)
        let errorMessage: String?
        let status: Operations.createCommandEvent.Input.Body.jsonPayload.statusPayload?
        switch commandEvent.status {
        case .success:
            errorMessage = nil
            status = .success
        case let .failure(message):
            errorMessage = message
            status = .failure
        }

        let response = try await client.createCommandEvent(
            .init(
                query: .init(
                    project_id: projectId
                ),
                body: .json(
                    .init(
                        client_id: commandEvent.clientId,
                        command_arguments: commandEvent.commandArguments,
                        duration: Double(commandEvent.durationInMs),
                        error_message: errorMessage,
                        git_branch: commandEvent.gitBranch,
                        git_commit_sha: commandEvent.gitCommitSHA,
                        git_ref: commandEvent.gitRef,
                        git_remote_url_origin: commandEvent.gitRemoteURLOrigin,
                        is_ci: commandEvent.isCI,
                        macos_version: commandEvent.macOSVersion,
                        name: commandEvent.name,
                        params: .init(
                            cacheable_targets: commandEvent.cacheableTargets,
                            local_cache_target_hits: commandEvent.localCacheTargetHits,
                            local_test_target_hits: commandEvent.localTestTargetHits,
                            remote_cache_target_hits: commandEvent.remoteCacheTargetHits,
                            remote_test_target_hits: commandEvent.remoteTestTargetHits,
                            test_targets: commandEvent.testTargets
                        ),
                        preview_id: commandEvent.params["preview_id"]?.value as? String,
                        status: status,
                        subcommand: commandEvent.subcommand,
                        swift_version: commandEvent.swiftVersion,
                        tuist_version: commandEvent.tuistVersion
                    )
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(commandEvent):
                return ServerCommandEvent(commandEvent)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateCommandEventServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw CreateCommandEventServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        }
    }
}
