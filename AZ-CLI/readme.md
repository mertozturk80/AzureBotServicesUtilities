# BotFramework Utilities: Azure CLI Samples

A catalog of PowerShell scripts for deploying and configuring Microsoft 365 Agents SDK, Azure healthcare agent service, and legacy Bot Builder SDK samples on Azure.

![Executing a sample script](https://github.com/user-attachments/assets/a39a7017-0adb-42f8-91c4-4f344788903d)

---

## Sample index

### Microsoft 365 Agents SDK

| Script | Purpose | Resources |
|---|---|---|
| [`DeployAgentsBotTemplateToNewRG.ps1`](./AgentsSDKSamples/DeployAgentsBotTemplateToNewRG.ps1) | Deploys the .NET Agents SDK quickstart to Windows App Service with an Entra application, Azure Bot registration, and Agents SDK authentication configuration. | <img width="559" height="253" alt="Azure resources created by the Agents SDK template sample" src="https://github.com/user-attachments/assets/d2a8db4f-69d3-4a30-96e7-5a9ea0e0127f" /> |
| [`DeployAgentsSDKtoDLASE.ps1`](./AgentsSDKSamples/DeployAgentsSDKtoDLASE.ps1) | Deploys the .NET `NamedPipeAgent` sample to Windows App Service with Direct Line App Service Extension, a test Web Chat client, and `/.bot` health verification. | |
| [`DeployOTelAgentToNewRG.ps1`](./AgentsSDKSamples/DeployOTelAgentToNewRG.ps1) | Deploys the .NET `OTelAgent` sample to Windows App Service and configures Application Insights for OpenTelemetry export. | |
| [`DeployPythonAutoSignInAgentToNewRG.ps1`](./AgentsSDKSamples/DeployPythonAutoSignInAgentToNewRG.ps1) | Deploys the Python auto-sign-in Agents SDK sample to Linux App Service and configures Microsoft Graph and GitHub OAuth connections. | |
| [`DeploySemanticKernelMultiturnToNewRG.ps1`](./AgentsSDKSamples/DeploySemanticKernelMultiturnToNewRG.ps1) | Deploys the .NET Semantic Kernel multiturn sample with Azure OpenAI, managed identity, and Agents SDK authentication. | <img width="324" height="169" alt="Azure resources created by the Semantic Kernel sample" src="https://github.com/user-attachments/assets/8db95b9b-2ba5-46ea-92ad-c33d1a478c23" /> |

Semantic Kernel multiturn sample result:

![Semantic Kernel bot responding](https://github.com/user-attachments/assets/6a27b3af-94bb-42e4-9e02-769d30819d42)

### Azure healthcare agent service

| Script | Purpose |
|---|---|
| [`DeployHealthBotToNewRG.ps1`](./HealthbotSamples/DeployHealthBotToNewRG.ps1) | Deploys an Azure healthcare agent service resource (formerly Azure Health Bot), validates regional availability, optionally assigns the signed-in user the Healthcare Agent Admin role, and links to the supported custom-scenario workflow. |

See the [healthcare agent service sample guide](./HealthbotSamples/README.md) for the custom `hello` scenario steps.

### Bot Builder SDK (legacy)

| Script | Purpose | Resources |
|---|---|---|
| [`DeployBBEchoBotTemplateToNewRG.ps1`](./BotBuilderSDKSamples/DeployBBEchoBotTemplateToNewRG.ps1) | Deploys the legacy Bot Builder Echo Bot sample to Azure App Service with Azure Bot registration and a classic Direct Line test client. | <img width="499" height="144" alt="Azure resources created by the Bot Builder Echo Bot sample" src="https://github.com/user-attachments/assets/42d04b7d-00c8-4028-9c0e-df6dbd3ca3da" /> |
| [`DeployBBEchoBotDirectlineASEToNewRG.ps1`](./BotBuilderSDKSamples/DeployBBEchoBotDirectlineASEToNewRG.ps1) | Deploys the legacy Echo Bot with Direct Line App Service Extension, named pipes, test clients, and supporting network resources. | <img width="516" height="335" alt="Azure resources created by the Direct Line ASE sample" src="https://github.com/user-attachments/assets/226855d7-f154-42d1-94fd-89487d238272" /> |
| [`PerformDirectlineASEIsolationSteps.ps1`](./BotBuilderSDKSamples/PerformDirectlineASEIsolationSteps.ps1) | Applies VNet integration, NSGs, private endpoints, private DNS, and public-access restrictions to the Direct Line ASE deployment. | <img width="523" height="329" alt="Azure resources created by the Direct Line ASE isolation sample" src="https://github.com/user-attachments/assets/9e47e75f-86cb-4ab8-9dbd-a421415b6391" /> |

See the [Bot Builder SDK deprecation and migration notice](./BotBuilderSDKSamples/README.md) before using these scripts.

> [!WARNING]
> The Bot Builder SDK scripts are retained for legacy support only. For new development, use the Microsoft 365 Agents SDK. For migration guidance, see [Azure Bot Framework SDK to Microsoft 365 Agents SDK migration guidance for .NET](https://learn.microsoft.com/microsoft-365/agents-sdk/bf-migration-dotnet).

---

## Notes

- Update the fixed parameters near the top of each script before running it.
- Handle secrets such as `AppSecret` and `DLSecret` securely. Do not commit or expose them in client code.
- Some operations, including Direct Line secret retrieval, can require portal actions or Key Vault storage depending on organizational policy.
- Scripts can create billable Azure resources. Review the selected regions and SKUs before execution.

## Quick start

Open PowerShell 7 and run the desired script from the repository root:

```powershell
pwsh ./AZ-CLI/AgentsSDKSamples/DeployAgentsBotTemplateToNewRG.ps1
```

---

Copyright (c) Mert Ozturk

## License

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
