// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IBebopSettlement} from "src/external/IBebopSettlement.sol";
import {Order} from "src/lib/Order.sol";
import {Signature} from "src/lib/Signature.sol";

contract MockBebopSettlement is IBebopSettlement {
    function SettleAggregateOrder(
        Order.Aggregate memory /*order*/,
        Signature.TypedSignature memory /*takerSig*/,
        Signature.MakerSignatures[] memory /*makerSigs*/
    ) external payable override returns (bool) {
        emit AggregateOrderExecuted(bytes32("mockOrder"));
        return true;
    }

    function SettleAggregateOrderWithTakerPermits(
        Order.Aggregate memory,
        Signature.TypedSignature memory,
        Signature.MakerSignatures[] memory,
        Signature.TakerPermitsInfo memory
    ) external payable override returns (bool) {
        emit AggregateOrderExecuted(bytes32("mockOrderWithPermits"));
        return true;
    }
}
