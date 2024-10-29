// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.

using System;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.Azure.WebJobs.Script.Config;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using WebJobs.Script.Tests;
using Xunit;
using static Microsoft.Azure.WebJobs.Script.Tests.Configuration.FunctionsHostingConfigOptionsTest;

namespace Microsoft.Azure.WebJobs.Script.Tests.Configuration
{
    public class RestrictHostLogsTests : IAsyncLifetime
    {
        public Task InitializeAsync()
        {
            return Task.CompletedTask;
        }

        public Task DisposeAsync()
        {
            // Reset the static _systemLogCategoryPrefixes field after each test to the default value
            typeof(ScriptLoggingBuilderExtensions)
                .GetField("_systemLogCategoryPrefixes", BindingFlags.Static | BindingFlags.NonPublic)
                .SetValue(null, ScriptConstants.SystemLogCategoryPrefixes);

            Environment.SetEnvironmentVariable(EnvironmentSettingNames.AzureWebJobsFeatureFlags, null);
            return Task.CompletedTask;
        }

        [Theory]
        [InlineData(true, false, true)] // RestrictHostLogs is true, FeatureFlag is not set, should result in **restricted** logs. This is the default behaviour of the host.
        [InlineData(false, true, false)] // RestrictHostLogs is false, FeatureFlag is set, should result in unrestricted logs
        [InlineData(true, true, false)] // RestrictHostLogs is true, FeatureFlag is set, should result in unrestricted logs
        [InlineData(false, false, false)] // RestrictHostLogs is false, FeatureFlag is not set, should result in unrestricted log
        public async Task RestirctHostLogs_SetsCorrectSystemLogPrefix(bool restrictHostLogs, bool setFeatureFlag, bool shouldResultInRestrictedSystemLogs)
        {
            using (TempDirectory tempDir = new TempDirectory())
            {
                //TestEnvironment environment = new ();
                string fileName = Path.Combine(tempDir.Path, "settings.txt");
                string fileContent = restrictHostLogs ? string.Empty : $"{ScriptConstants.HostingConfigRestrictHostLogs}=false";

                if (setFeatureFlag)
                {
                    //environment.SetEnvironmentVariable(EnvironmentSettingNames.AzureWebJobsFeatureFlags, ScriptConstants.FeatureFlagEnableHostLogs);
                    Environment.SetEnvironmentVariable(EnvironmentSettingNames.AzureWebJobsFeatureFlags, ScriptConstants.FeatureFlagEnableHostLogs);
                }

                IHost host = GetScriptHostBuilder(fileName, fileContent).Build();
                var testService = host.Services.GetService<TestService>();

                await host.StartAsync();
                await Task.Delay(1000);

                Assert.Equal(restrictHostLogs, testService.Options.Value.RestrictHostLogs);
                Assert.Equal(setFeatureFlag, FeatureFlags.IsEnabled(ScriptConstants.FeatureFlagEnableHostLogs));

                var result = typeof(ScriptLoggingBuilderExtensions).GetField("_systemLogCategoryPrefixes", BindingFlags.Static | BindingFlags.NonPublic).GetValue(null);

                if (shouldResultInRestrictedSystemLogs)
                {
                    Assert.Equal(ScriptConstants.RestrictedSystemLogCategoryPrefixes, result);
                }
                else
                {
                    Assert.Equal(ScriptConstants.SystemLogCategoryPrefixes, result);
                }

                await host.StopAsync();
            }
        }
    }
}