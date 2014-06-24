﻿using System;
using System.Globalization;
using Microsoft.Azure.Jobs.Host.Executors;
using Microsoft.Azure.Jobs.Host.Protocols;

namespace Microsoft.Azure.Jobs.Host.IntegrationTests
{
    // Like  FunctionInstance plus output stats?
    // Provide the function instance for reply. 
    // Get list of inputs for logging. 
    // Times should all be in UTC.
    // This object gets mutated as the function executes. 
    internal class ExecutionInstanceLogEntity
    {
        public override string ToString()
        {
            var name = String.Format(CultureInfo.InvariantCulture, "{0}.{1}", FunctionInstance.Method.DeclaringType.Name, FunctionInstance.Method.Name);
            string startTime = this.StartTime.HasValue ? this.StartTime.Value.ToUniversalTime().ToString() : this.QueueTime.ToUniversalTime().ToString();
            return string.Format("{0} @ {1}", name, startTime);
        }

        public Guid HostId { get; set; }

        public Guid HostInstanceId { get; set; }

        public WebJobRunIdentifier ExecutingJobRunId { get; set; }

        // rowKey = FunctionInstance.Guid?  uniquely identify the instance. 
        // Instance provides both the RowKey, as well as the invocation request information (like args)
        public IFunctionInstance FunctionInstance { get; set; }

        // If function threw an exception, set to type.fullname of that exception.
        // It's important that this is top-level and queryable because it's a key scenario to find failures. 
        // Provides a quick way to know if function failed. Get exception details from the logging. 
        public string ExceptionType { get; set; }
        public string ExceptionMessage { get; set; }

        // For retrieving the console output.
        // Likely URL to a blob that the Console output was written to.
        public string OutputUrl { get; set; }

        // URL of BLOB with parameter logging data.
        public string ParameterLogUrl { get; set; }

        public DateTime QueueTime { get; set; }

        public DateTime? StartTime { get; set; }

        // Time that the job was completed (approximately when the user's code has finished running). 
        // Null if job is not yet complete.
        // To avoid clocksqew,  start and end time should be set by the same execution node. 
        // Set StartTime before the user code (including bindings) starts to run, set EndTime after it finishes. 
        public DateTime? EndTime { get; set; }

        // Get a row key for azure tables
        // $$$ Should FunctionDefinition have this too? That one uses ToString(), and it's inconsistent.
        public string GetKey()
        {
            return this.FunctionInstance.Id.ToString();
        }
    }
}
