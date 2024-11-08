#!/bin/bash

cp -r /home/site/wwwroot/lib /FuncExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/*/NetFxWorker/CustomLib/Content
cp -r /home/site/wwwroot/Artifacts /FuncExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/*/NetFxWorker/CustomLib/Content
/azure-functions-host/Microsoft.Azure.WebJobs.Script.WebHost
