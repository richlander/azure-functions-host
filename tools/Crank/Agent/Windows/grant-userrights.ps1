param(
    [string]$UserName
)

$ErrorActionPreference = 'Stop'

# 'Log on as a service policy' should include the user.
$right = "SeServiceLogonRight"

# Path to the temporary security template file
$templatePath = "C:\Temp\SecurityTemplate.inf"

# Create the security template file
@"
[Unicode]
Unicode=yes
[Version]
signature="\$CHICAGO\$"
Revision=1
[Privilege Rights]
$right = *$UserName
"@ | Out-File -FilePath $templatePath -Encoding Unicode

# Apply the security template
secedit /configure /db secedit.sdb /cfg $templatePath /areas USER_RIGHTS

# Clean up
Remove-Item -Path $templatePath

Write-Output "Logon as a service right granted to $UserName"
