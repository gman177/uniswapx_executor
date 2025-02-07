// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "lib/solmate/src/auth/Owned.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {WETH} from "lib/solmate/src/tokens/WETH.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";
import {IBebopSettlement} from "../external/IBebopSettlement.sol";
import {Order} from "../lib/Order.sol";
import {Signature} from "../lib/Signature.sol";

contract SwapRouter02Executor is IReactorCallback, Owned {
    using CurrencyLibrary for address;

    error CallerNotWhitelisted();
    error MsgSenderNotReactor();

    mapping(address => bool) public whitelistedCallers;

    IBebopSettlement private immutable bebop;
    IReactor private immutable reactor;
    WETH private immutable weth;

    constructor(
        address[] memory _whitelistedCallers,
        IReactor _reactor,
        address _owner,
        IBebopSettlement _bebop
    ) Owned(_owner) {
        for (uint256 i = 0; i < _whitelistedCallers.length; i++) {
            whitelistedCallers[_whitelistedCallers[i]] = true;
        }
        reactor = _reactor;
        bebop = _bebop;
        weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    }

    modifier onlyWhitelistedCaller() {
        if (!whitelistedCallers[msg.sender]) {
            revert CallerNotWhitelisted();
        }
        _;
    }

    modifier onlyReactor() {
        if (msg.sender != address(reactor)) {
            revert MsgSenderNotReactor();
        }
        _;
    }

    function execute(
        SignedOrder calldata order,
        address leftoverRecipient,
        bytes calldata bebopCallbackData
    )
        external
        payable
        onlyWhitelistedCaller
    {
        bytes memory fullCallbackData = abi.encode(leftoverRecipient, bebopCallbackData);
        reactor.executeWithCallback(order, fullCallbackData);
    }

    function executeBatch(
        SignedOrder[] calldata orders,
        address leftoverRecipient,
        bytes calldata bebopCallbackData
    )
        external
        payable
        onlyWhitelistedCaller
    {
        bytes memory fullCallbackData = abi.encode(leftoverRecipient, bebopCallbackData);
        reactor.executeBatchWithCallback(orders, fullCallbackData);
    }

    function reactorCallback(ResolvedOrder[] calldata, bytes calldata callbackData)
        external
        onlyReactor
    {
        (address leftoverRecipient, bytes memory bebopCallbackData) =
            abi.decode(callbackData, (address, bytes));

        (address tokenIn, address tokenOut, bytes memory aggregatorData) =
            abi.decode(bebopCallbackData, (address, address, bytes));

        (
            Order.Aggregate memory order,
            Signature.TypedSignature memory takerSig,
            Signature.MakerSignatures[] memory makerSigs
        ) = abi.decode(aggregatorData, (Order.Aggregate, Signature.TypedSignature, Signature.MakerSignatures[]));

        if (tokenIn == address(0)) {
            weth.deposit{value: order.taker_amounts[0][0]}();
        }

        bebop.SettleAggregateOrder(order, takerSig, makerSigs);

        if (tokenOut == address(0)) {
            weth.withdraw(weth.balanceOf(address(this)));
            CurrencyLibrary.transferNative(address(reactor), order.maker_amounts[0][0]);
        } else {
            IERC20(tokenOut).approve(address(reactor), order.maker_amounts[0][0]);
        }

        if (tokenIn == address(0)) {
            uint256 leftoverETH = address(this).balance;
            if (leftoverETH > 0) {
                (bool success, ) = leftoverRecipient.call{value: leftoverETH}("");
                require(success, "Leftover ETH transfer failed");
            }
        } else {
            uint256 leftoverIn = IERC20(tokenIn).balanceOf(address(this));
            if (leftoverIn > 0) {
                IERC20(tokenIn).transfer(leftoverRecipient, leftoverIn);
            }
        }

        if (tokenOut == address(0)) {
            uint256 leftoverETH = address(this).balance;
            if (leftoverETH > 0) {
                (bool success, ) = leftoverRecipient.call{value: leftoverETH}("");
                require(success, "Leftover ETH transfer failed");
            }
        } else {
            uint256 leftoverOut = IERC20(tokenOut).balanceOf(address(this));
            if (leftoverOut > 0) {
                IERC20(tokenOut).transfer(leftoverRecipient, leftoverOut);
            }
        }
    }

    // Owner-only functions
    function approve(address token, address recipient) external onlyOwner {
        IERC20(token).approve(recipient, type(uint256).max);
    }

    function withdrawFunds(address token) external onlyOwner {
        if (token == address(0)) {
            uint256 ethBalance = address(this).balance;
            (bool success, ) = msg.sender.call{value: ethBalance}("");
            require(success, "ETH transfer failed");
        } else {
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            IERC20(token).transfer(msg.sender, tokenBalance);
        }
    }

    receive() external payable {}
}
