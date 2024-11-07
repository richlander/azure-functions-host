#!/bin/bash

./install-native-dependencies.sh --runtime
cp -r /home/site/wwwroot/lib /FuncExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/*/NetFxWorker/CustomLib/Content
