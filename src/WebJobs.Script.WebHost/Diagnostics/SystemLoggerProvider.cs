// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.

using System;
using System.Collections.Concurrent;
using System.Collections.Immutable;
using System.Linq;
using Microsoft.Azure.WebJobs.Logging;
using Microsoft.Azure.WebJobs.Script.Config;
using Microsoft.Azure.WebJobs.Script.Configuration;
using Microsoft.Azure.WebJobs.Script.Eventing;
using Microsoft.Azure.WebJobs.Script.Workers;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace Microsoft.Azure.WebJobs.Script.WebHost.Diagnostics
{
    public class SystemLoggerProvider : ILoggerProvider, ISupportExternalScope
    {
        private readonly string _hostInstanceId;
        private readonly IEventGenerator _eventGenerator;
        private readonly IEnvironment _environment;
        private readonly IDebugStateProvider _debugStateProvider;
        private readonly IScriptEventManager _eventManager;
        private readonly IOptionsMonitor<AppServiceOptions> _appServiceOptions;
        private readonly IOptionsMonitor<FunctionsHostingConfigOptions> _hostingOptions;
        private readonly ImmutableArray<string> _allowedSystemLogPrefixes;
        private IExternalScopeProvider _scopeProvider;
        private ConcurrentDictionary<string, bool> _filteredCategoryCache = new ConcurrentDictionary<string, bool>();

        public SystemLoggerProvider(IOptions<ScriptJobHostOptions> scriptOptions, IEventGenerator eventGenerator, IEnvironment environment, IDebugStateProvider debugStateProvider,
            IScriptEventManager eventManager, IOptionsMonitor<AppServiceOptions> appServiceOptions, IOptionsMonitor<FunctionsHostingConfigOptions> hostingOptions)
            : this(scriptOptions.Value.InstanceId, eventGenerator, environment, debugStateProvider, eventManager, appServiceOptions, hostingOptions)
        {
        }

        protected SystemLoggerProvider(string hostInstanceId, IEventGenerator eventGenerator, IEnvironment environment, IDebugStateProvider debugStateProvider,
            IScriptEventManager eventManager, IOptionsMonitor<AppServiceOptions> appServiceOptions, IOptionsMonitor<FunctionsHostingConfigOptions> hostingOptions)
        {
            _eventGenerator = eventGenerator;
            _environment = environment;
            _hostInstanceId = hostInstanceId;
            _debugStateProvider = debugStateProvider;
            _eventManager = eventManager;
            _appServiceOptions = appServiceOptions;
            _hostingOptions = hostingOptions;

            // Feature flag should take precedence over the host configuration
            _allowedSystemLogPrefixes = !FeatureFlags.IsEnabled(ScriptConstants.FeatureFlagEnableHostLogs, _environment) && _hostingOptions.CurrentValue.RestrictHostLogs
                            ? ScriptConstants.RestrictedSystemLogCategoryPrefixes
                            : ScriptConstants.SystemLogCategoryPrefixes;
        }

        public ILogger CreateLogger(string categoryName)
        {
            if (IsUserLogCategory(categoryName) || IsLogCategoryRestricted(categoryName))
            {
                // The SystemLogger is not used for user logs or if the logs are restricted.
                return NullLogger.Instance;
            }

            return new SystemLogger(_hostInstanceId, categoryName, _eventGenerator, _environment, _debugStateProvider, _eventManager, _scopeProvider, _appServiceOptions);
        }

        private bool IsUserLogCategory(string categoryName)
        {
            return LogCategories.IsFunctionUserCategory(categoryName) || categoryName.Equals(WorkerConstants.FunctionConsoleLogCategoryName, StringComparison.OrdinalIgnoreCase);
        }

        private bool IsLogCategoryRestricted(string categoryName)
        {
            return !_filteredCategoryCache.GetOrAdd(categoryName, c => _allowedSystemLogPrefixes.Any(p => categoryName.StartsWith(p)));
        }

        public void Dispose()
        {
        }

        public void SetScopeProvider(IExternalScopeProvider scopeProvider)
        {
            _scopeProvider = scopeProvider;
        }
    }
}
