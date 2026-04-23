# Power Automate Desktop Custom Action — VS Code Sample

A minimal, end-to-end sample showing how to build, sign, and package a **Power Automate Desktop (PAD) custom action module** using **VS Code and the .NET CLI** — **no Visual Studio required**.

The sample action `LogEventToFile` appends a message to a text file. Use it as a template for your own actions.

---

## Why this repo exists

The official Microsoft docs assume you have Visual Studio installed and use `signtool.exe` from the Windows SDK. This sample shows the equivalent workflow using only:

- VS Code
- The .NET SDK (`dotnet` CLI)
- Built-in PowerShell cmdlets (`Set-AuthenticodeSignature`)
- Built-in `makecab.exe`

---

## Requirements

| Requirement | Why | How to get it |
|---|---|---|
| **Windows 10/11** | PAD is Windows-only; uses `makecab.exe`, `Set-AuthenticodeSignature` | Built in |
| **VS Code** | Editor | https://code.visualstudio.com/ |
| **.NET SDK 6.0 or later** | Builds the .NET Framework 4.7.2 project via SDK-style csproj | `winget install Microsoft.DotNet.SDK.8` |
| **PowerShell 5.1+** | Runs the build/sign/package scripts | Built in |
| **Power Automate Desktop** | To consume the custom action | Microsoft Store or https://powerautomate.microsoft.com/ |
| **A code-signing certificate** | PAD refuses to load unsigned modules | See [Certificates](#certificates) below |

> You do **NOT** need Visual Studio.
> You do **NOT** need the Windows SDK / `signtool.exe`.

### Hard rules enforced by Power Automate Desktop

1. **Target framework must be `net472`** (.NET Framework 4.7.2). Other targets will not load.
2. **Assembly name must match the pattern `Modules.*` or `*.Modules.*`** (e.g., `Modules.SampleActions`).
3. **`AssemblyTitle` cannot contain `.`** — use underscores (e.g., `Modules_SampleActions`).
4. **Both the module DLL and the `.cab` package must be signed** with a code-signing certificate.
5. **The signing certificate must be trusted on every machine that runs the flow** — see [Trust the certificate on each PAD machine](#5-trust-the-certificate-on-each-pad-machine).

---

## Repo structure

```
.
├── Modules.SampleActions/
│   ├── Modules.SampleActions.csproj   # SDK-style project, targets net472
│   └── LogEventToFile.cs              # Sample action implementation
├── BuildAndPackage.ps1                # End-to-end: build → sign DLLs → CAB → sign CAB
├── makeCabFile.ps1                    # Packs DLLs into a signed CAB (from MS docs)
├── CreateSelfSignedCert.ps1           # OPTIONAL — dev/test only (see warning below)
├── InstallCertOnTargetMachine.ps1     # Installs a cert into the trust stores PAD requires
├── .gitignore
├── LICENSE
└── README.md
```

---

## Quick start

```powershell
# 1. Clone and open in VS Code
git clone https://github.com/<your-org>/pad-custom-action-vscode-sample.git
cd pad-custom-action-vscode-sample

# 2. Restore + build
dotnet build .\Modules.SampleActions -c Release

# 3. Build, sign, and package in one shot
#    (Use your own .pfx; see "Certificates" below for production guidance.)
$pwd = Read-Host -AsSecureString -Prompt "PFX password"
.\BuildAndPackage.ps1 -PfxPath .\path\to\YourCodeSigningCert.pfx -PfxPassword $pwd

# 4. Trust the cert on each machine that will run PAD (admin required, ONCE per machine)
.\InstallCertOnTargetMachine.ps1 -CerPath .\path\to\YourCodeSigningCert.cer
```

The signed `.cab` is produced at `Output\Modules.SampleActions.cab`. Upload it at **https://make.powerautomate.com → ⋯ More → Custom actions → Upload**.

---

## Certificates

> **⚠️ READ THIS — Production vs. Development**
>
> Power Automate Desktop refuses to load any custom-action module that is not signed by a code-signing certificate trusted by the OS on every machine that runs the flow.
>
> **For production**, you should use a code-signing certificate from a recognized public Certificate Authority (e.g., DigiCert, Sectigo, GlobalSign, IdenTrust). Public CA certificates chain to roots that are already trusted on every Windows machine, so the cert "just works" without the extra trust-store steps below.
>
> **The self-signed-certificate workflow in this repo is for development and testing only.** A self-signed cert will only be trusted on machines where you have manually imported it into the local certificate stores (and doing that on customer / production machines is an anti-pattern).

### Option A — Production (recommended): use a CA-issued cert

If your organization already has a code-signing cert (typically a `.pfx` from your IT/PKI team), skip the self-signed steps entirely. Just:

1. Place the `.pfx` somewhere safe (do **not** commit it).
2. Run `BuildAndPackage.ps1 -PfxPath .\YourCert.pfx -PfxPassword $pwd`.
3. Distribute the `.cab` — no `InstallCertOnTargetMachine.ps1` needed because the issuing CA is already trusted on Windows.

### Option B — Development / proof-of-concept: self-signed cert

> Only use this for dev/test. Never ship a self-signed cert workflow to production end users.

```powershell
# 1. Create the cert (admin required because we also import it for the dev box)
.\CreateSelfSignedCert.ps1 -OutputDir .\Certs -CertName PADDevSignCert

# 2. Build, sign, package
$pwd = Read-Host -AsSecureString -Prompt "PFX password"
.\BuildAndPackage.ps1 -PfxPath .\Certs\PADDevSignCert.pfx -PfxPassword $pwd

# 3. On EACH developer/test machine that will run PAD, import the .cer into trust stores
.\InstallCertOnTargetMachine.ps1 -CerPath .\Certs\PADDevSignCert.cer
```

---

## Step-by-step walkthrough

### 1. Create the project

A SDK-style `.csproj` works with the `dotnet` CLI and VS Code:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net472</TargetFramework>
    <AssemblyTitle>Modules_SampleActions</AssemblyTitle>
    <Description>Sample Power Automate Desktop custom action module</Description>
    <GenerateAssemblyInfo>true</GenerateAssemblyInfo>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.PowerPlatform.PowerAutomate.Desktop.Actions.SDK" Version="*" />
  </ItemGroup>
</Project>
```

### 2. Write an action

Inherit from `ActionBase`, decorate inputs/outputs with attributes, and implement `Execute()`:

```csharp
using System;
using System.IO;
using Microsoft.PowerPlatform.PowerAutomate.Desktop.Actions.SDK;
using Microsoft.PowerPlatform.PowerAutomate.Desktop.Actions.SDK.Attributes;

namespace Modules.SampleActions
{
    [Action(Id = "LogEventToFile", Order = 1, Category = "Logging",
        FriendlyName = "Log Event To File",
        Description = "Appends a log message to the specified text file.")]
    [Throws("LogEventError")]
    public class LogEventToFile : ActionBase
    {
        [InputArgument(FriendlyName = "Log File Name")]
        public string LogFileName { get; set; }

        [InputArgument(FriendlyName = "Log Message")]
        public string LogMessage { get; set; }

        [OutputArgument(FriendlyName = "Status Code")]
        public bool StatusCode { get; set; }

        public override void Execute(ActionContext context)
        {
            try
            {
                File.AppendAllText(LogFileName, LogMessage + Environment.NewLine);
                StatusCode = true;
            }
            catch (Exception ex)
            {
                StatusCode = false;
                throw new ActionException("LogEventError", ex.Message, ex);
            }
        }
    }
}
```

### 3. Build

```powershell
dotnet build .\Modules.SampleActions -c Release
```

Output: `Modules.SampleActions\bin\Release\net472\Modules.SampleActions.dll`

### 4. Sign + package

```powershell
$pwd = Read-Host -AsSecureString -Prompt "PFX password"
.\BuildAndPackage.ps1 -PfxPath .\path\to\Cert.pfx -PfxPassword $pwd
```

This script:
1. Runs `dotnet build` (Release).
2. Signs every DLL in the build output with `Set-AuthenticodeSignature` (SHA256).
3. Packages DLLs into `Output\Modules.SampleActions.cab` via `makecab.exe` (the SDK DLL is excluded — PAD provides it).
4. Signs the `.cab`.

### 5. Trust the certificate on each PAD machine

> Skip this step if you used a CA-issued cert (Option A above).

PAD checks **two** stores when validating a custom action signature:

| Store | Purpose |
|---|---|
| `Cert:\LocalMachine\Root` | Trusted Root Certification Authorities — establishes the chain of trust |
| `Cert:\LocalMachine\TrustedPublisher` | Trusted Publishers — explicitly authorizes the signer's code |

Both are required. The most common cause of `the desktop flow module package is not correctly signed` is a missing entry in **TrustedPublisher**.

Run on every machine that will execute the flow (admin required, once per machine):

```powershell
.\InstallCertOnTargetMachine.ps1 -CerPath .\path\to\Cert.cer
```

Then **restart Power Automate Desktop**. Trust state is cached at process start.

### 6. Upload to Power Automate

1. Go to **https://make.powerautomate.com**.
2. Open the **⋯ (More)** menu in the left rail → **Custom actions**.
3. Click **Upload** and select `Output\Modules.SampleActions.cab`.
4. Open Power Automate Desktop → **Assets Library** → add the action to your environment.
5. Drag the **Log Event To File** action into a flow and test.

---

## Troubleshooting

### "The desktop flow module package is not correctly signed"

The signing certificate isn't fully trusted on the machine running PAD. Check both stores:

```powershell
$thumb = '<your-cert-thumbprint>'
foreach ($store in 'Root','TrustedPublisher') {
    $ok = Get-ChildItem "Cert:\LocalMachine\$store" | Where-Object { $_.Thumbprint -eq $thumb }
    "{0,-32} {1}" -f "LocalMachine\$store", $(if($ok){'PRESENT'}else{'MISSING'})
}
```

If either store says MISSING, run `InstallCertOnTargetMachine.ps1` as Administrator, then restart PAD.

You can also verify the CAB itself:

```powershell
Get-AuthenticodeSignature .\Output\Modules.SampleActions.cab
```

`Status` should be `Valid`. If you see `A certificate chain processed, but terminated in a root certificate which is not trusted by the trust provider`, the cert is not in `LocalMachine\Root`.

### Action does not appear in PAD

- Confirm `<TargetFramework>` is `net472`.
- Confirm the assembly name matches `Modules.*` or `*.Modules.*`.
- Confirm `AssemblyTitle` uses underscores, not dots.
- After uploading the new CAB, **restart PAD**.

### `dotnet` not found

Install the .NET SDK and open a new terminal:

```powershell
winget install Microsoft.DotNet.SDK.8
```

---

## Updating the action

1. Edit the `.cs` file (or add a new one).
2. Re-run `BuildAndPackage.ps1` — it produces a new signed `.cab`.
3. Upload the new `.cab` to Power Automate (it replaces the previous version).
4. Restart Power Automate Desktop.

---

## References

- [Create custom actions for Power Automate Desktop](https://learn.microsoft.com/power-automate/desktop-flows/create-custom-actions) — official Microsoft docs
- [Microsoft.PowerPlatform.PowerAutomate.Desktop.Actions.SDK](https://www.nuget.org/packages/Microsoft.PowerPlatform.PowerAutomate.Desktop.Actions.SDK) — NuGet package
- [Authenticode digital signatures](https://learn.microsoft.com/windows-hardware/drivers/install/authenticode)

---

## License

[MIT](LICENSE)
