// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IReactor} from "src/interfaces/IReactor.sol";
import {SignedOrder, ResolvedOrder} from "src/base/ReactorStructs.sol";
import {IReactorCallback} from "src/interfaces/IReactorCallback.sol";

/**
 * @notice Minimal mock of the Reactor that calls back into the executor.
 *         In a real scenario, the Reactor would do more (resolving orders, etc.).
 */
contract MockReactor is IReactor {
    // Store callback data for test assertions
    bytes public lastCallbackData;
    address public lastCallbackContract;
    uint256 public lastBatchSize;

    function execute(SignedOrder calldata /*order*/) external payable override {}

    function executeWithCallback(SignedOrder calldata, bytes calldata callbackData)
        external
        payable
        override
    {
        lastCallbackData = callbackData;
        lastCallbackContract = msg.sender;

        // Build a dummy ResolvedOrder[] for the callback
        ResolvedOrder[] memory dummy = new ResolvedOrder[](1);
        IReactorCallback(msg.sender).reactorCallback(dummy, callbackData);
    }

    function executeBatch(SignedOrder[] calldata /*orders*/) external payable override {}

    function executeBatchWithCallback(SignedOrder[] calldata orders, bytes calldata callbackData)
        external
        payable
        override
    {
        lastCallbackData = callbackData;
        lastCallbackContract = msg.sender;
        lastBatchSize = orders.length;

        ResolvedOrder[] memory dummy = new ResolvedOrder[](orders.length);
        IReactorCallback(msg.sender).reactorCallback(dummy, callbackData);
    }
}
