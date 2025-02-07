// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Contract under test
import {SwapRouter02Executor} from "src/executors/SwapRouter02Executor.sol";

// Mocks
import {MockReactor} from "test/mocks/MockReactor.sol";
import {MockBebopSettlement} from "test/mocks/MockBebopSettlement.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

// Structs and libraries
import {SignedOrder, ResolvedOrder} from "src/base/ReactorStructs.sol";
import {IReactor} from "src/interfaces/IReactor.sol";
import {IBebopSettlement} from "src/external/IBebopSettlement.sol";
import {Order} from "src/lib/Order.sol";
import {Signature} from "src/lib/Signature.sol";

contract SwapRouter02ExecutorTest is Test {
    address internal owner;
    address internal whitelisted1;
    address internal nonWhitelisted;

    SwapRouter02Executor internal executor;
    MockReactor internal mockReactor;
    MockBebopSettlement internal mockBebop;
    MockERC20 internal usdc;
    MockERC20 internal usdt;

    function setUp() public {
        owner = address(this);
        whitelisted1 = makeAddr("whitelisted1");
        nonWhitelisted = makeAddr("nonWhitelisted");

        mockReactor = new MockReactor();
        mockBebop = new MockBebopSettlement();
        usdc = new MockERC20("Mock USDC", "USDC", 6);
        usdt = new MockERC20("Mock USDT", "USDT", 6);

        address[] memory wl = new address[](1);
        wl[0] = whitelisted1;

        executor = new SwapRouter02Executor(
            wl,
            IReactor(address(mockReactor)),
            owner,
            IBebopSettlement(address(mockBebop))
        );
    }

    function test_NonWhitelistedReverts() public {
        SignedOrder memory dummyOrder;
        vm.prank(nonWhitelisted);
        vm.expectRevert(SwapRouter02Executor.CallerNotWhitelisted.selector);
        executor.execute(dummyOrder, nonWhitelisted, new bytes(0));
    }

    function test_WhitelistedExecutesSuccessfully() public {
        SignedOrder memory dummyOrder;
        bytes memory aggregatorData = buildBebopAggregatorData(1 ether, address(0), address(0));

        vm.deal(whitelisted1, 1 ether);
        vm.prank(whitelisted1);
        executor.execute{value: 1 ether}(dummyOrder, whitelisted1, aggregatorData);

        assertEq(address(executor).balance, 0);
        assertGt(whitelisted1.balance, 0); // Ensure ETH leftover refunded
    }

    function test_LeftoverUSDCRefund() public {
        SignedOrder memory dummyOrder;
        usdc.mint(address(executor), 1000 * 1e6);

        bytes memory aggregatorData = buildBebopAggregatorData(1 ether, address(usdc), address(0));

        vm.prank(whitelisted1);
        executor.execute(dummyOrder, whitelisted1, aggregatorData);

        assertEq(usdc.balanceOf(address(executor)), 0);
        assertGt(usdc.balanceOf(whitelisted1), 0); // Ensure USDC leftover refunded
    }

    function test_LeftoverUSDTRefund() public {
        SignedOrder memory dummyOrder;
        usdt.mint(address(executor), 1000 * 1e6);

        bytes memory aggregatorData = buildBebopAggregatorData(1 ether, address(usdt), address(0));

        vm.prank(whitelisted1);
        executor.execute(dummyOrder, whitelisted1, aggregatorData);

        assertEq(usdt.balanceOf(address(executor)), 0);
        assertGt(usdt.balanceOf(whitelisted1), 0); // Ensure USDT leftover refunded
    }

    function buildBebopAggregatorData(uint256 amount, address tokenIn, address tokenOut) public view returns (bytes memory) {
        Order.Aggregate memory agg;

        agg.expiry = block.timestamp + 1 days;
        agg.taker_address = address(0x123); // Example taker address

        // Initialize 1D array for maker_addresses
        agg.maker_addresses = new address[](1);
        agg.maker_addresses[0] = address(0x456); // Example maker address

        agg.maker_nonces = new uint256[](1);
        agg.maker_nonces[0] = 1; // Example nonce

        // Initialize 2D arrays
        agg.taker_tokens = new address[][](2);
        agg.taker_tokens[0] = new address[](2);
        agg.taker_tokens[0][0] = tokenIn;
        agg.taker_tokens[0][1] = tokenOut;

        agg.maker_tokens = new address[][](2);
        agg.maker_tokens[0] = new address[](2);
        agg.maker_tokens[0][0] = tokenOut;
        agg.maker_tokens[0][1] = tokenIn;

        agg.taker_amounts = new uint256[][](1);
        agg.taker_amounts[0] = new uint256[](1);
        agg.taker_amounts[0][0] = amount;

        agg.maker_amounts = new uint256[][](1);
        agg.maker_amounts[0] = new uint256[](1);
        agg.maker_amounts[0][0] = amount;

        agg.receiver = address(0x789); // Example receiver address
        agg.commands = ""; // Empty commands for now

        Signature.TypedSignature memory takerSig = Signature.TypedSignature({
            signatureType: Signature.Type.EIP712,
            signatureBytes: bytes("fakeTakerSig")
        });

        Signature.MakerSignatures[] memory makerSigs = new Signature.MakerSignatures[](0);

        bytes memory aggregatorData = abi.encode(agg, takerSig, makerSigs);
        return abi.encode(tokenIn, tokenOut, aggregatorData);
    }
}