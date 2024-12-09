git clone --branch dev https://github.com/Azure/azure-functions-host.git
git clone --branch main https://github.com/kshyju/FuncPerf.git

dotnet publish ./azure-functions-host/src/WebJobs.Script.WebHost/WebJobs.Script.WebHost.csproj -c release -o ./out/azure-functions-host
dotnet publish ./FuncPerf/src/HelloHttp/HelloHttp.csproj -c release -o ./out/hello_http
