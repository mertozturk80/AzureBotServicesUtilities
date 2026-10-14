# Bot Builder SDK Samples

> [!WARNING]
> The Bot Framework SDK (Bot Builder SDK) is deprecated. These scripts are retained only to support existing legacy bots. Do not use them as the starting point for new development.

For new bots and agents, use the Microsoft 365 Agents SDK scripts in [`../AgentsSDKSamples`](../AgentsSDKSamples/).

## Migration guidance

Treat migration as an application modernization effort rather than only replacing NuGet packages. Authentication, application configuration, hosting, state, middleware, and legacy services may require changes.

Use Microsoft's official .NET migration guide:

- [Azure Bot Framework SDK to Microsoft 365 Agents SDK migration guidance for .NET](https://learn.microsoft.com/microsoft-365/agents-sdk/bf-migration-dotnet)

The guide covers:

- Bot Framework-to-Agents SDK package replacements.
- Authentication and connection configuration.
- Agent application registration and routing.
- State, storage, middleware, and adapter changes.
- Reusing existing Azure Bot resources during migration.

## Legacy scripts

- `DeployBBEchoBotTemplateToNewRG.ps1`
- `DeployBBEchoBotDirectlineASEToNewRG.ps1`
- `PerformDirectlineASEIsolationSteps.ps1`

Before changing or redeploying an existing bot, plan its migration to the Agents SDK and validate the migrated application in a non-production environment.
