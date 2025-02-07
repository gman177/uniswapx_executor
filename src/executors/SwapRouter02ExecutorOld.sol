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

/// @notice A fill contract that uses SwapRouter02 to execute trades
contract SwapRouter02Executor is IReactorCallback, Owned {
    using CurrencyLibrary for address;

    /// @notice thrown if reactorCallback is called with a non-whitelisted filler
    error CallerNotWhitelisted();
    /// @notice thrown if reactorCallback is called by an address other than the reactor
    error MsgSenderNotReactor();

    IBebopSettlement private immutable bebop;
    address private immutable whitelistedCaller;
    IReactor private immutable reactor;
    WETH private immutable weth;

    modifier onlyWhitelistedCaller() {
        if (msg.sender != whitelistedCaller) {
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

    constructor(address _whitelistedCaller, IReactor _reactor, address _owner, IBebopSettlement _bebop)
        Owned(_owner)
    {
        whitelistedCaller = _whitelistedCaller;
        reactor = _reactor;
        bebop = _bebop;
        weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    }

    /// @notice assume that we already have all output tokens
    function execute(SignedOrder calldata order, bytes calldata callbackData) external onlyWhitelistedCaller {
        reactor.executeWithCallback(order, callbackData);
    }

    /// @notice assume that we already have all output tokens
    function executeBatch(SignedOrder[] calldata orders, bytes calldata callbackData) external onlyWhitelistedCaller {
        reactor.executeBatchWithCallback(orders, callbackData);
    }

    /// @notice fill UniswapX orders using SwapRouter02
    /// @param callbackData It has the below encoded:
    /// address[] memory tokensToApproveForSwapRouter02: Max approve these tokens to swapRouter02
    /// address[] memory tokensToApproveForReactor: Max approve these tokens to reactor
    /// bytes[] memory multicallData: Pass into swapRouter02.multicall()
    function reactorCallback(ResolvedOrder[] calldata, bytes calldata callbackData) external onlyReactor {
        (
            address tokenIn,
            address tokenOut,
            bytes memory bebopData
        ) = abi.decode(callbackData, (address, address, bytes));
        (
            Order.Aggregate memory order, 
            Signature.TypedSignature memory takerSig,
            Signature.MakerSignatures[] memory makerSigs
        ) = abi.decode(bebopData, (Order.Aggregate, Signature.TypedSignature, Signature.MakerSignatures[]));
        unchecked {
            if (tokenIn == 0x0000000000000000000000000000000000000000){
                weth.deposit{value: order.taker_amounts[0][0]}();
            }
        }
        bebop.SettleAggregateOrder(order, takerSig, makerSigs);

        // transfer any native balance to the reactor
        // it will refund any excess
        if (tokenOut == 0x0000000000000000000000000000000000000000){
            weth.withdraw(weth.balanceOf(address(this)));
            CurrencyLibrary.transferNative(address(reactor), order.maker_amounts[0][0]);
        }else{
            IERC20(tokenOut).approve(address(reactor), order.maker_amounts[0][0]);
        }
    }

    /// @notice Approves token to recipient. Can only be called by owner.
    /// @param recipient The address of recipient
    function approve(address token, address recipient) external onlyOwner {
        IERC20(token).approve(recipient, type(uint256).max);
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address payable recipient) external onlyOwner {
        recipient.transfer(address(this).balance);
    }

    /// @notice Necessary for this contract to receive ETH when calling unwrapWETH()
    receive() external payable {}
}
