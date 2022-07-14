﻿// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.

using Microsoft.Azure.Functions.WorkerHarness.Grpc.Messages;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using WorkerHarness.Core.GrpcService;
using WorkerHarness.Core.Matching;
using WorkerHarness.Core.StreamingMessageService;
using WorkerHarness.Core.Validators;

namespace WorkerHarness.Core.Actions
{
    /// <summary>
    /// Default implemenation of IActionProvider
    /// </summary>
    public class RpcActionProvider : IActionProvider
    {
        private readonly IValidatorFactory _validatorFactory;
        private readonly IMessageMatcher _messageMatcher;
        private readonly IStreamingMessageProvider _rpcMessageProvider;
        private readonly Channel<StreamingMessage> _inboundChannel;
        private readonly Channel<StreamingMessage> _outboundChannel;

        internal static string ArgumentMissingMessagesProperty = "Missing the \"messages\" array in an Rpc action";

        public string Type => ActionTypes.Rpc;

        public RpcActionProvider(IValidatorFactory validatorFactory, 
            IMessageMatcher messageMatcher,
            IStreamingMessageProvider rpcMessageProvider,
            GrpcServiceChannel channel)
        {
            _validatorFactory = validatorFactory;
            _messageMatcher = messageMatcher;
            _rpcMessageProvider = rpcMessageProvider;
            _inboundChannel = channel.InboundChannel;
            _outboundChannel = channel.OutboundChannel;
        }

        /// <summary>
        /// Create a Default Action
        /// </summary>
        /// <param name="actionNode" cref="JsonNode">contains information to create an action</param>
        /// <returns cref="IAction">a DefaultAction object</returns>
        /// <exception cref=""></exception>
        public IAction Create(JsonNode actionNode)
        {
            // 1. create a DefaultActionData that encapsulate info about an action
            RpcActionData actionData = CreateRpcActionData(actionNode);
            // 2. create a DefaultAction object
            return new RpcAction(_validatorFactory,
                                _messageMatcher,
                                _rpcMessageProvider,
                                actionData,
                                _inboundChannel,
                                _outboundChannel);
        }

        /// <summary>
        /// Convert an JsonNode object to a DefaultActionData object
        /// </summary>
        /// <param name="actionNode" cref="JsonNode"></param>
        /// <returns>a DefaultActionData</returns>
        private static RpcActionData CreateRpcActionData(JsonNode actionNode)
        {
            ValidateRpcActionNode(actionNode);

            JsonSerializerOptions serializerOptions = new() { PropertyNameCaseInsensitive = true };
            RpcActionData actionData = JsonSerializer.Deserialize<RpcActionData>(actionNode, serializerOptions)!;

            return actionData;
        }

        private static void ValidateRpcActionNode(JsonNode actionNode)
        {
            if (actionNode["messages"] == null || actionNode["messages"] is not JsonArray)
            {
                throw new ArgumentException(ArgumentMissingMessagesProperty);
            }
        }

    }
}