// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.

using System.IO;
using Microsoft.Azure.WebJobs.Logging;
using Microsoft.Azure.WebJobs.Script.Config;
using Microsoft.Azure.WebJobs.Script.Configuration;
using Microsoft.Azure.WebJobs.Script.WebHost.Diagnostics;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using Xunit;

namespace Microsoft.Azure.WebJobs.Script.Tests
{
    public class SystemLoggerProviderTests
    {
        private readonly IOptions<ScriptJobHostOptions> _options;
        private readonly IEnvironment _environment = new TestEnvironment();
        private readonly SystemLoggerProvider _provider;
        private bool _inDiagnosticMode;

        public SystemLoggerProviderTests()
        {
            var scriptOptions = new ScriptJobHostOptions
            {
                RootLogPath = Path.GetTempPath()
            };

            _options = new OptionsWrapper<ScriptJobHostOptions>(scriptOptions);
            _environment.SetEnvironmentVariable(EnvironmentSettingNames.AzureWebJobsFeatureFlags, ScriptConstants.FeatureFlagEnableHostLogs);

            var debugStateProvider = new Mock<IDebugStateProvider>(MockBehavior.Strict);
            debugStateProvider.Setup(p => p.InDiagnosticMode).Returns(() => _inDiagnosticMode);

            var appServiceOptions = new TestOptionsMonitor<AppServiceOptions>(new AppServiceOptions());
            var hostingOptions = new TestOptionsMonitor<FunctionsHostingConfigOptions>(new FunctionsHostingConfigOptions());
            _provider = new SystemLoggerProvider(_options, null, _environment, debugStateProvider.Object, null, appServiceOptions, hostingOptions);
        }

        [Fact]
        public void CreateLogger_ReturnsSystemLogger_ForNonUserCategories()
        {
            Assert.IsType<SystemLogger>(_provider.CreateLogger(LogCategories.CreateFunctionCategory("TestFunction")));
            Assert.IsType<SystemLogger>(_provider.CreateLogger(ScriptConstants.LogCategoryHostGeneral));
           //Assert.IsType<SystemLogger>(_provider.CreateLogger("NotAFunction.TestFunction.User"));
        }

        [Fact]
        public void CreateLogger_ReturnsNullLogger_ForUserCategory()
        {
            Assert.IsType<NullLogger>(_provider.CreateLogger(LogCategories.CreateFunctionUserCategory("TestFunction")));
        }

        [Fact]
        public void CreateLogger_DefaultsLogLevelToDebug()
        {
            var logger = _provider.CreateLogger(LogCategories.Startup);
            Assert.True(logger.IsEnabled(LogLevel.Information));
            Assert.True(logger.IsEnabled(LogLevel.Warning));
            Assert.True(logger.IsEnabled(LogLevel.Error));
            Assert.True(logger.IsEnabled(LogLevel.Critical));
            Assert.True(logger.IsEnabled(LogLevel.Debug));
            Assert.False(logger.IsEnabled(LogLevel.Trace));
        }

        [Fact]
        public void CreateLogger_DiagnosticMode_LogsEverything()
        {
            var logger = _provider.CreateLogger(LogCategories.Startup);
            Assert.True(logger.IsEnabled(LogLevel.Information));
            Assert.True(logger.IsEnabled(LogLevel.Warning));
            Assert.True(logger.IsEnabled(LogLevel.Error));
            Assert.True(logger.IsEnabled(LogLevel.Critical));
            Assert.True(logger.IsEnabled(LogLevel.Debug));
            Assert.False(logger.IsEnabled(LogLevel.Trace));

            _inDiagnosticMode = true;
            logger = _provider.CreateLogger(LogCategories.Startup);
            Assert.True(logger.IsEnabled(LogLevel.Information));
            Assert.True(logger.IsEnabled(LogLevel.Warning));
            Assert.True(logger.IsEnabled(LogLevel.Error));
            Assert.True(logger.IsEnabled(LogLevel.Critical));
            Assert.True(logger.IsEnabled(LogLevel.Debug));
            Assert.True(logger.IsEnabled(LogLevel.Trace));
        }

        [Theory]
        [InlineData(true, false, true)] // RestrictHostLogs is true, FeatureFlag is not set, should result in **restricted** logs. This is the default behaviour of the host.
        [InlineData(false, true, false)] // RestrictHostLogs is false, FeatureFlag is set, should result in unrestricted logs
        [InlineData(true, true, false)] // RestrictHostLogs is true, FeatureFlag is set, should result in unrestricted logs
        [InlineData(false, false, false)] // RestrictHostLogs is false, FeatureFlag is not set, should result in unrestricted log
        public void RestirctHostLogs_SetsCorrectSystemLogPrefix(bool restrictHostLogs, bool setFeatureFlag, bool shouldResultInRestrictedSystemLogs)
        {
            TestEnvironment environment = new ();
            var debugStateProvider = new Mock<IDebugStateProvider>(MockBehavior.Strict);
            debugStateProvider.Setup(p => p.InDiagnosticMode).Returns(() => false);

            var hostingOptions = new FunctionsHostingConfigOptions();
            hostingOptions.RestrictHostLogs = restrictHostLogs;
            var hostingOptionsMonitor = new TestOptionsMonitor<FunctionsHostingConfigOptions>(hostingOptions);

            if (setFeatureFlag)
            {
                environment.SetEnvironmentVariable(EnvironmentSettingNames.AzureWebJobsFeatureFlags, ScriptConstants.FeatureFlagEnableHostLogs);
            }

            var appServiceOptions = new TestOptionsMonitor<AppServiceOptions>(new AppServiceOptions());
            var provider = new SystemLoggerProvider(_options, null, environment, debugStateProvider.Object, null, appServiceOptions, hostingOptionsMonitor);

            var logger = provider.CreateLogger(LogCategories.HostGeneral);
            //LogCategories.Startup

            Assert.Equal(restrictHostLogs, hostingOptionsMonitor.CurrentValue.RestrictHostLogs);
            Assert.Equal(setFeatureFlag, FeatureFlags.IsEnabled(ScriptConstants.FeatureFlagEnableHostLogs, environment));

            if (shouldResultInRestrictedSystemLogs)
            {
                Assert.IsType<NullLogger>(logger);
            }
            else
            {
                Assert.IsType<SystemLogger>(logger);
            }
        }
    }
}