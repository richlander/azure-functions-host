﻿// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.

using System.Collections.Concurrent;
using System.Collections.Immutable;
using System.Linq;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Azure.WebJobs.Script;
using Microsoft.Azure.WebJobs.Script.Config;
using Microsoft.Azure.WebJobs.Script.Configuration;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

namespace Microsoft.Extensions.Logging
{
    public static class ScriptLoggingBuilderExtensions
    {
        private static ConcurrentDictionary<string, bool> _filteredCategoryCache = new ConcurrentDictionary<string, bool>();
        private static ImmutableArray<string> _systemLogCategoryPrefixes = ScriptConstants.SystemLogCategoryPrefixes;

        public static ILoggingBuilder AddDefaultWebJobsFilters(this ILoggingBuilder builder, bool restrictHostLogs = false)
        {
            if (restrictHostLogs)
            {
                _systemLogCategoryPrefixes = ScriptConstants.RestrictedSystemLogCategoryPrefixes;
            }

            builder.SetMinimumLevel(LogLevel.None);
            builder.AddFilter((c, l) => Filter(c, l, LogLevel.Information));
            return builder;
        }

        public static ILoggingBuilder AddDefaultWebJobsFilters<T>(this ILoggingBuilder builder, LogLevel level, bool restrictHostLogs = false) where T : ILoggerProvider
        {
            if (restrictHostLogs)
            {
                _systemLogCategoryPrefixes = ScriptConstants.RestrictedSystemLogCategoryPrefixes;
            }

            builder.AddFilter<T>(null, LogLevel.None);
            builder.AddFilter<T>((c, l) => Filter(c, l, level));
            return builder;
        }

        internal static bool Filter(string category, LogLevel actualLevel, LogLevel minLevel)
        {
            return actualLevel >= minLevel && IsFiltered(category);
        }

        private static bool IsFiltered(string category)
        {
            return _filteredCategoryCache.GetOrAdd(category, c => _systemLogCategoryPrefixes.Any(p => category.StartsWith(p)));
        }

        public static void AddConsoleIfEnabled(this ILoggingBuilder builder, HostBuilderContext context)
        {
            AddConsoleIfEnabled(builder, context.HostingEnvironment.IsDevelopment(), context.Configuration);
        }

        public static void AddConsoleIfEnabled(this ILoggingBuilder builder, WebHostBuilderContext context)
        {
            AddConsoleIfEnabled(builder, context.HostingEnvironment.IsDevelopment(), context.Configuration);
        }

        private static void AddConsoleIfEnabled(ILoggingBuilder builder, bool isDevelopment, IConfiguration configuration)
        {
            // console logging defaults to false, except for self host
            bool enableConsole = isDevelopment;

            string consolePath = ConfigurationPath.Combine(ConfigurationSectionNames.JobHost, "Logging", "Console", "IsEnabled");
            IConfigurationSection configSection = configuration.GetSection(consolePath);

            if (configSection.Exists())
            {
                // if it has been explicitly configured that value overrides default
                enableConsole = configSection.Get<bool>();
            }

            if (enableConsole)
            {
                builder.AddConsole();
            }
        }
    }
}
