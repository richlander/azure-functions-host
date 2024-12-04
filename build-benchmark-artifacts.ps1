

dotnet publish ./src/WebJobs.Script.WebHost/WebJobs.Script.WebHost.csproj -c release -o ./functions_host_published

# TO DO: Publish Function App to relative path and use that for AzureWebJobsScriptRoot