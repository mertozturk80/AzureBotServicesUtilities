# Healthcare Agent Service Samples

This folder contains deployment samples for Azure healthcare agent service, formerly Azure Health Bot.

## Deploy a healthcare agent service

[`DeployHealthBotToNewRG.ps1`](./DeployHealthBotToNewRG.ps1) creates:

- A resource group.
- A `Microsoft.HealthBot/healthBots` resource.
- An optional Healthcare Agent Admin role assignment for the signed-in user.

The script uses the free `F0` SKU by default. Before running it, update `$SubscriptionId`, `$Location`, `$Suffix`, and `$SkuName` as needed.

```powershell
pwsh ./AZ-CLI/HealthBotSamples/DeployHealthBotToNewRG.ps1
```

References:

- [Create your first healthcare agent service](https://learn.microsoft.com/azure/health-bot/quickstart-createyourhealthcarebot)
- [Author your first custom scenario](https://learn.microsoft.com/azure/health-bot/quickstart-createyourfirstscenario)

## Create the custom `hello` scenario

Scenario authoring is performed in the healthcare agent service Management Portal. The documented Azure resource provider creates the service itself but does not expose scenarios as ARM child resources. Microsoft also does not document a public scenario-authoring API. The deployment script therefore avoids unsupported private portal endpoints.

After running the script:

1. Open the Azure portal URL printed by the script.
2. Select **healthcare agent service Management Portal**.
3. Open **Scenarios** and select **Add**.
4. Set:
   - **Name:** `Hello World`
   - **Description:** `Introduces the healthcare agent and asks whether the user wants to schedule a doctor visit.`
   - **Scenario ID:** `hello`
5. Create the scenario.
6. Add a **Statement** element with the text `Hello, World!`.
7. Add a **Yes/No Prompt** that asks `Would you like to schedule a meeting with a doctor?`.
8. Store the answer in a variable named `ShouldScheduleDoctor`.
9. Connect both outcomes:
   - **Yes:** Add a statement such as `Please contact your healthcare provider to arrange an appointment.`
   - **No:** Add a statement such as `Okay. Let me know if you need anything else.`
10. Connect both branches to the scenario end, then select **Save**.
11. Select **Run** to test the scenario.

From the main chat window, explicitly start it with:

```text
begin hello
```

The scenario is only a demonstration and must not provide diagnosis, emergency triage, or individualized medical advice. Have clinical, privacy, security, and compliance stakeholders review production healthcare scenarios.

## Moving scenarios between environments

The Management Portal supports scenario **Export** and **Import** using its generated JSON format. Create and validate the scenario in a non-production environment, export it from the portal, and import that export into the target environment. Do not invent or hand-maintain an undocumented scenario JSON schema.

