﻿using Microsoft.Azure.Functions.WorkerHarness.Grpc.Messages;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace WorkerHarness.Core
{
    internal class DefaultAction : IAction
    {
        // _validatorManager is responsible for validating message. TODO: implement the validation functionality
        private IValidatorManager _validatorManager;

        // _grpcMessageProvider create the right StreamingMessage object
        private IGrpcMessageProvider _grpcMessageProvider;

        // _actionData encapsulates data for each action in the Scenario file.
        private DefaultActionData _actionData;

        // _variableManager evaluates all registered expressions once the variable values are available.
        private IVariableManager _variableManager;

        internal DefaultAction(IValidatorManager validatorManager, 
            IGrpcMessageProvider grpcMessageProvider, 
            DefaultActionData actionData,
            IVariableManager variableManager)
        {
            _validatorManager = validatorManager;
            _grpcMessageProvider = grpcMessageProvider;
            _actionData = actionData;
            _variableManager = variableManager;
        }

        // Type of action, type "Default" in this case
        public string? Type { get => _actionData.Type; }

        // Displayed name of the action
        public string? Name { get => _actionData.Name; }

        // Execuation timeout for an action
        public int? Timeout { get => _actionData.Timeout; }

        // Placeholder that stores StreamingMessage to be sent to Grpc Layer
        private IList<StreamingMessage> _grpcOutgoingMessages = new List<StreamingMessage>();

        // Placeholder that stores IncomingMessage to be matched and validated against messages from Grpc Layer.
        private IList<IncomingMessage> _unvalidatedMessages = new List<IncomingMessage>();

        public void Execute()
        {
            ProcessOutgoingMessages();
            ProcessIncomingMessages();
        }

        /// <summary>
        /// Create StreamingMessage objects for each action in the scenario file.
        /// Add them to the _grpcOutgoingMessages to be sent to Grpc Service layer later.
        /// If users set any variables, resolve those variables.
        /// 
        /// </summary>
        /// <exception cref="NullReferenceException"></exception>
        private void ProcessOutgoingMessages()
        {
            //JsonSerializerOptions options = new JsonSerializerOptions() { WriteIndented = true };
            //options.Converters.Add(new JsonStringEnumConverter());

            foreach (OutgoingMessage message in _actionData.OutgoingMessages)
            {
                // create a StreamingMessage that will be sent to a language worker
                if (string.IsNullOrEmpty(message.ContentCase))
                {
                    throw new NullReferenceException($"The property {nameof(message.ContentCase)} is required to create a {typeof(StreamingMessage)} object");
                }

                StreamingMessage streamingMessage = _grpcMessageProvider.Create(message.ContentCase, message.Content);

                string messageId = message.Id ?? Guid.NewGuid().ToString();

                // resolve "SetVariables" property
                VariableHelper.ResolveVariableMap(message.SetVariables, messageId, streamingMessage);

                // add the variables inside "SetVariables" to VariableManager
                if (message.SetVariables != null)
                {
                    foreach (KeyValuePair<string, string> variable in message.SetVariables)
                    {
                        _variableManager.AddVariable(variable.Key, variable.Value);
                    }
                }

                _variableManager.AddVariable(messageId, streamingMessage);

                _grpcOutgoingMessages.Add(streamingMessage);
            }
        }

        // TODO: debugging methods, to be deleted later
        private void PrintDictionary(IDictionary<string, object> resolvedVariables)
        {
            JsonSerializerOptions options = new JsonSerializerOptions() { WriteIndented = true };
            options.Converters.Add(new JsonStringEnumConverter());

            foreach (KeyValuePair<string, object> pair in resolvedVariables)
            {
                Console.WriteLine($"Variable: {pair.Key}\nValue: {JsonSerializer.Serialize(pair.Value, options)}");
            }
        }

        /// <summary>
        /// Register incoming messages that are to be validated against actual grpc messages.
        /// 
        /// Subscribe variable expressions (if any) mentioned in the scenario file.
        /// Variable expressions are allowed in:
        ///     - Expected field in the Match property: this feature allows user to identify an incoming message based on
        ///     the property of another message, which enable dependency between messages
        ///     - Expected field in the Validators property: this feature allows user to validate an incoming message based on
        ///     the property of another message.
        ///     
        /// </summary>
        private void ProcessIncomingMessages()
        {
            //JsonSerializerOptions options = new JsonSerializerOptions() { WriteIndented = true };
            foreach (IncomingMessage message in _actionData.IncomingMessages)
            {
                var messageId = message.Id ?? Guid.NewGuid().ToString();

                // in message.Match, update any default variable '$.' to '$.{messageId}'
                if (message.Match != null)
                {
                    message.Match.Query = VariableHelper.UpdateSingleDefaultVariableExpression(message.Match.Query ?? string.Empty, messageId);
                    message.Match.Expected = VariableHelper.UpdateSingleDefaultVariableExpression(message.Match.Expected ?? string.Empty, messageId);
                    message.Match.ExpectedExpression = new Expression(message.Match.Expected);

                    _variableManager.Subscribe(message.Match.ExpectedExpression);
                }

                // in message.Validators, update any default variable '$.' to '$.{messageId}'
                if (message.Validators != null)
                {
                    foreach (var validator in message.Validators)
                    {
                        if (validator != null)
                        {
                            validator.Query = VariableHelper.UpdateSingleDefaultVariableExpression(validator.Query ?? string.Empty, messageId);
                            validator.Expected = VariableHelper.UpdateSingleDefaultVariableExpression(validator.Expected ?? string.Empty, messageId);
                            validator.ExpectedExpression = new Expression(validator.Expected);

                            _variableManager.Subscribe(validator.ExpectedExpression);
                        }
                    }
                }

                _unvalidatedMessages.Add(message);
            }
        }
    }
}