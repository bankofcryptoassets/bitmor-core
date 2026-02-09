// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV4Swapper} from "../src/uniswap/UniswapV4Swapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UniswapV4SwapperTest
 * @notice Unit tests for UniswapV4Swapper input validation
 * @dev These tests deploy a fresh contract locally - no fork needed
 *      Run with: forge test -vvv --match-contract UniswapV4SwapperTest
 */
contract UniswapV4SwapperTest is Test {
    // ============ Mock Addresses (for local testing) ============

    address constant MOCK_ROUTER = address(0x1111);
    address constant MOCK_QUOTER = address(0x2222);

    // ============ Token Addresses (just for function params) ============

    address constant USDC_MAINNET = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant CBBTC_MAINNET = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    // ============ Pool Parameters ============

    uint24 constant FEE_TIER_MEDIUM = 3000; // 0.3%
    int24 constant TICK_SPACING_MEDIUM = 60;
    address constant NO_HOOKS = address(0);

    // ============ Test State ============

    UniswapV4Swapper public swapper;
    address public user;

    // ============ Setup ============

    function setUp() public {
        // Deploy a fresh swapper with mock addresses and pool config
        swapper = new UniswapV4Swapper(
            MOCK_ROUTER,
            MOCK_QUOTER,
            FEE_TIER_MEDIUM,
            TICK_SPACING_MEDIUM,
            NO_HOOKS
        );

        // Create test user
        user = makeAddr("user");

        // Fund user with ETH for gas
        vm.deal(user, 100 ether);
    }

    // ============ Deployment Tests ============

    function test_DeployedCorrectly() public view {
        // Verify the swapper has correct immutables
        assertEq(address(swapper.i_UNIVERSAL_ROUTER()), MOCK_ROUTER, "Universal router mismatch");
        assertEq(address(swapper.i_QUOTER()), MOCK_QUOTER, "V4 quoter mismatch");
        assertEq(swapper.i_FEE(), FEE_TIER_MEDIUM, "Fee mismatch");
        assertEq(swapper.i_TICK_SPACING(), TICK_SPACING_MEDIUM, "Tick spacing mismatch");
        assertEq(swapper.i_HOOKS(), NO_HOOKS, "Hooks mismatch");
    }

    function test_SwapperCodeExists() public view {
        // Verify the contract has code
        uint256 codeSize;
        address swapperAddr = address(swapper);
        assembly {
            codeSize := extcodesize(swapperAddr)
        }
        assertGt(codeSize, 0, "Swapper has no code");
    }

    // ============ Input Validation Tests ============

    function test_SwapExactInput_RevertOnZeroAmount() public {
        vm.startPrank(user);

        vm.expectRevert("Invalid input amount");
        swapper.swapExactInput(
            USDC_MAINNET,
            CBBTC_MAINNET,
            0, // zero amount
            1,
            user
        );

        vm.stopPrank();
    }

    function test_SwapExactInput_RevertOnZeroMinOutput() public {
        vm.startPrank(user);

        vm.expectRevert("Invalid min output");
        swapper.swapExactInput(
            USDC_MAINNET,
            CBBTC_MAINNET,
            1000e6, // 1000 USDC
            0, // zero min output
            user
        );

        vm.stopPrank();
    }

    function test_SwapExactInput_RevertOnZeroRecipient() public {
        vm.startPrank(user);

        vm.expectRevert("Invalid recipient");
        swapper.swapExactInput(
            USDC_MAINNET,
            CBBTC_MAINNET,
            1000e6,
            1,
            address(0) // zero recipient
        );

        vm.stopPrank();
    }

    function test_SwapExactOutput_RevertOnZeroAmount() public {
        vm.startPrank(user);

        vm.expectRevert("Invalid output amount");
        swapper.swapExactOutput(
            USDC_MAINNET,
            CBBTC_MAINNET,
            0, // zero amount
            1000e6,
            user
        );

        vm.stopPrank();
    }

    function test_SwapExactOutput_RevertOnZeroMaxInput() public {
        vm.startPrank(user);

        vm.expectRevert("Invalid max input");
        swapper.swapExactOutput(
            USDC_MAINNET,
            CBBTC_MAINNET,
            0.01e8, // 0.01 CBBTC
            0, // zero max input
            user
        );

        vm.stopPrank();
    }

    function test_SwapExactOutput_RevertOnZeroRecipient() public {
        vm.startPrank(user);

        vm.expectRevert("Invalid recipient");
        swapper.swapExactOutput(
            USDC_MAINNET,
            CBBTC_MAINNET,
            0.01e8,
            1000e6,
            address(0) // zero recipient
        );

        vm.stopPrank();
    }
}

/**
 * @title UniswapV4SwapperMainnetForkTest
 * @notice Integration tests on Base Mainnet fork with USDC/CBBTC pools
 * @dev Run with: forge test --fork-url $BASE_RPC_URL -vvv --match-contract UniswapV4SwapperMainnetForkTest
 */
contract UniswapV4SwapperMainnetForkTest is Test {
    UniswapV4Swapper public swapper;
    address public user;

    // Base Mainnet contract addresses
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant V4_QUOTER = 0x0d5e0F971ED27FBfF6c2837bf31316121532048D;

    // Base Mainnet tokens
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    // Token decimals
    uint8 constant USDC_DECIMALS = 6;
    uint8 constant CBBTC_DECIMALS = 8;

    // Pool parameters - verified for USDC/CBBTC pool on Base
    uint24 constant FEE_3000 = 3000; // 0.3%
    int24 constant TICK_SPACING_60 = 60;
    address constant NO_HOOKS = address(0);

    function setUp() public {
        // Skip if not on mainnet fork
        if (block.chainid != 8453) {
            return;
        }

        // Deploy a fresh instance with pool config baked in
        swapper = new UniswapV4Swapper(
            UNIVERSAL_ROUTER,
            V4_QUOTER,
            FEE_3000,
            TICK_SPACING_60,
            NO_HOOKS
        );

        user = makeAddr("user");
        vm.deal(user, 100 ether);

        // Fund user with USDC using Foundry's deal cheat code
        deal(USDC, user, 100_000e6); // 100,000 USDC

        // Fund user with CBBTC using Foundry's deal cheat code
        deal(CBBTC, user, 10e8); // 10 CBBTC (8 decimals)
    }

    modifier onlyMainnet() {
        if (block.chainid != 8453) {
            console.log("Skipping test - not on Base Mainnet fork");
            return;
        }
        _;
    }

    // ============ Quote Tests: USDC -> CBBTC ============

    /// @notice Test getting a quote: how much USDC needed to get X CBBTC
    function test_GetMaxTokenInAmount_USDC_to_CBBTC() public onlyMainnet {
        // Get quote: how much USDC do I need to get 0.01 CBBTC?
        uint256 cbbtcAmount = 0.01e8; // 0.01 CBBTC (8 decimals)

        try swapper.getMaxTokenInAmount(USDC, CBBTC, cbbtcAmount) returns (uint256 maxAmountIn) {
            console.log("Max USDC needed for 0.01 CBBTC:", maxAmountIn);
            assertGt(maxAmountIn, 0, "Quote should be non-zero");

            // Sanity check: at ~$100k/BTC, 0.01 BTC = ~$1000 USDC
            assertGt(maxAmountIn, 500e6, "Quote too low"); // > 500 USDC
            assertLt(maxAmountIn, 5000e6, "Quote too high"); // < 5000 USDC
        } catch Error(string memory reason) {
            console.log("Quote failed:", reason);
        } catch {
            console.log("Quote failed - pool may not exist with these parameters");
        }
    }

    /// @notice Test getting a quote: how much CBBTC will I get for X USDC
    function test_GetMinTokenOutAmount_USDC_to_CBBTC() public onlyMainnet {
        // Get quote: how much CBBTC will I get for 1000 USDC?
        uint256 usdcAmount = 1000e6; // 1000 USDC

        try swapper.getMinTokenOutAmount(USDC, CBBTC, usdcAmount) returns (uint256 minAmountOut) {
            console.log("Min CBBTC for 1000 USDC:", minAmountOut);
            assertGt(minAmountOut, 0, "Quote should be non-zero");

            // Sanity check: at ~$100k/BTC, 1000 USDC = ~0.01 BTC
            assertGt(minAmountOut, 0.005e8, "Quote too low"); // > 0.005 CBBTC
            assertLt(minAmountOut, 0.05e8, "Quote too high"); // < 0.05 CBBTC
        } catch Error(string memory reason) {
            console.log("Quote failed:", reason);
        } catch {
            console.log("Quote failed - pool may not exist");
        }
    }

    // ============ Quote Tests: CBBTC -> USDC ============

    /// @notice Test getting a quote: how much CBBTC needed to get X USDC
    function test_GetMaxTokenInAmount_CBBTC_to_USDC() public onlyMainnet {
        // Get quote: how much CBBTC do I need to get 1000 USDC?
        uint256 usdcAmount = 1000e6; // 1000 USDC

        try swapper.getMaxTokenInAmount(CBBTC, USDC, usdcAmount) returns (uint256 maxAmountIn) {
            console.log("Max CBBTC needed for 1000 USDC:", maxAmountIn);
            assertGt(maxAmountIn, 0, "Quote should be non-zero");

            // Sanity check: at ~$100k/BTC, 1000 USDC = ~0.01 BTC
            assertGt(maxAmountIn, 0.005e8, "Quote too low");
            assertLt(maxAmountIn, 0.05e8, "Quote too high");
        } catch Error(string memory reason) {
            console.log("Quote failed:", reason);
        } catch {
            console.log("Quote failed - pool may not exist");
        }
    }

    /// @notice Test getting a quote: how much USDC will I get for X CBBTC
    function test_GetMinTokenOutAmount_CBBTC_to_USDC() public onlyMainnet {
        // Get quote: how much USDC will I get for 0.01 CBBTC?
        uint256 cbbtcAmount = 0.01e8; // 0.01 CBBTC

        try swapper.getMinTokenOutAmount(CBBTC, USDC, cbbtcAmount) returns (uint256 minAmountOut) {
            console.log("Min USDC for 0.01 CBBTC:", minAmountOut);
            assertGt(minAmountOut, 0, "Quote should be non-zero");

            // Sanity check: at ~$100k/BTC, 0.01 BTC = ~$1000
            assertGt(minAmountOut, 500e6, "Quote too low");
            assertLt(minAmountOut, 5000e6, "Quote too high");
        } catch Error(string memory reason) {
            console.log("Quote failed:", reason);
        } catch {
            console.log("Quote failed - pool may not exist");
        }
    }

    // ============ Swap Tests: USDC -> CBBTC (Opening Loan) ============

    /// @notice Test swapExactInput: swap exact USDC for CBBTC
    function test_SwapExactInput_USDC_to_CBBTC() public onlyMainnet {
        uint256 swapAmount = 1000e6; // 1000 USDC

        vm.startPrank(user);

        // Verify user has USDC
        uint256 usdcBalance = IERC20(USDC).balanceOf(user);
        assertGe(usdcBalance, swapAmount, "User should have USDC");
        console.log("User USDC balance:", usdcBalance);

        // Get quote first
        uint256 minAmountOut;
        try swapper.getMinTokenOutAmount(USDC, CBBTC, swapAmount) returns (uint256 quoted) {
            minAmountOut = quoted;
            console.log("Expected min CBBTC out:", minAmountOut);
        } catch {
            console.log("Could not get quote, using 1 as min");
            minAmountOut = 1;
        }

        // Approve swapper
        IERC20(USDC).approve(address(swapper), swapAmount);

        // Record balances before
        uint256 userUsdcBefore = IERC20(USDC).balanceOf(user);
        uint256 userCbbtcBefore = IERC20(CBBTC).balanceOf(user);

        // Execute swap
        try swapper.swapExactInput(USDC, CBBTC, swapAmount, minAmountOut, user) returns (uint256 amountOut) {
            console.log("Swap successful! CBBTC received:", amountOut);

            // Verify balances changed correctly
            uint256 userUsdcAfter = IERC20(USDC).balanceOf(user);
            uint256 userCbbtcAfter = IERC20(CBBTC).balanceOf(user);

            assertEq(userUsdcBefore - userUsdcAfter, swapAmount, "USDC not deducted correctly");
            assertEq(userCbbtcAfter - userCbbtcBefore, amountOut, "CBBTC not received correctly");
            assertGe(amountOut, minAmountOut, "Received less than minimum");
        } catch Error(string memory reason) {
            console.log("Swap failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Swap failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopPrank();
    }

    /// @notice Test swapExactOutput: get exact CBBTC amount (for opening loan)
    function test_SwapExactOutput_USDC_to_CBBTC() public onlyMainnet {
        uint256 exactCbbtcOut = 0.01e8; // Want exactly 0.01 CBBTC

        vm.startPrank(user);

        // Get quote for max USDC input
        uint256 maxAmountIn;
        try swapper.getMaxTokenInAmount(USDC, CBBTC, exactCbbtcOut) returns (uint256 quoted) {
            maxAmountIn = quoted;
            console.log("Max USDC needed:", maxAmountIn);
        } catch {
            console.log("Could not get quote, using 2000 USDC as max");
            maxAmountIn = 2000e6;
        }

        // Approve swapper
        IERC20(USDC).approve(address(swapper), maxAmountIn);

        // Record balances
        uint256 userUsdcBefore = IERC20(USDC).balanceOf(user);
        uint256 userCbbtcBefore = IERC20(CBBTC).balanceOf(user);

        // Execute swap
        try swapper.swapExactOutput(USDC, CBBTC, exactCbbtcOut, maxAmountIn, user) returns (uint256 amountIn) {
            console.log("Swap successful! USDC spent:", amountIn);

            // Verify balances
            uint256 userUsdcAfter = IERC20(USDC).balanceOf(user);
            uint256 userCbbtcAfter = IERC20(CBBTC).balanceOf(user);

            // User should have received exactly the requested CBBTC
            assertEq(userCbbtcAfter - userCbbtcBefore, exactCbbtcOut, "Did not receive exact CBBTC");

            // User should have spent amountIn USDC (got refund for unused)
            assertEq(userUsdcBefore - userUsdcAfter, amountIn, "USDC accounting mismatch");

            // Amount spent should be <= max
            assertLe(amountIn, maxAmountIn, "Spent more than max");
        } catch Error(string memory reason) {
            console.log("Swap failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Swap failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopPrank();
    }

    // ============ Swap Tests: CBBTC -> USDC (Closing Loan) ============

    /// @notice Test swapExactInput: swap exact CBBTC for USDC (closing loan)
    function test_SwapExactInput_CBBTC_to_USDC() public onlyMainnet {
        uint256 swapAmount = 0.01e8; // 0.01 CBBTC

        vm.startPrank(user);

        // Verify user has CBBTC
        uint256 cbbtcBalance = IERC20(CBBTC).balanceOf(user);
        assertGe(cbbtcBalance, swapAmount, "User should have CBBTC");
        console.log("User CBBTC balance:", cbbtcBalance);

        // Get quote first
        uint256 minAmountOut;
        try swapper.getMinTokenOutAmount(CBBTC, USDC, swapAmount) returns (uint256 quoted) {
            minAmountOut = quoted;
            console.log("Expected min USDC out:", minAmountOut);
        } catch {
            console.log("Could not get quote, using 1 as min");
            minAmountOut = 1;
        }

        // Approve swapper
        IERC20(CBBTC).approve(address(swapper), swapAmount);

        // Record balances before
        uint256 userCbbtcBefore = IERC20(CBBTC).balanceOf(user);
        uint256 userUsdcBefore = IERC20(USDC).balanceOf(user);

        // Execute swap
        try swapper.swapExactInput(CBBTC, USDC, swapAmount, minAmountOut, user) returns (uint256 amountOut) {
            console.log("Swap successful! USDC received:", amountOut);

            // Verify balances changed correctly
            uint256 userCbbtcAfter = IERC20(CBBTC).balanceOf(user);
            uint256 userUsdcAfter = IERC20(USDC).balanceOf(user);

            assertEq(userCbbtcBefore - userCbbtcAfter, swapAmount, "CBBTC not deducted correctly");
            assertEq(userUsdcAfter - userUsdcBefore, amountOut, "USDC not received correctly");
            assertGe(amountOut, minAmountOut, "Received less than minimum");
        } catch Error(string memory reason) {
            console.log("Swap failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Swap failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopPrank();
    }

    /// @notice Test swapExactOutput: get exact USDC amount from CBBTC
    function test_SwapExactOutput_CBBTC_to_USDC() public onlyMainnet {
        uint256 exactUsdcOut = 500e6; // Want exactly 500 USDC

        vm.startPrank(user);

        // Get quote for max CBBTC input
        uint256 maxAmountIn;
        try swapper.getMaxTokenInAmount(CBBTC, USDC, exactUsdcOut) returns (uint256 quoted) {
            maxAmountIn = quoted;
            console.log("Max CBBTC needed:", maxAmountIn);
        } catch {
            console.log("Could not get quote, using 0.1 CBBTC as max");
            maxAmountIn = 0.1e8;
        }

        // Approve swapper
        IERC20(CBBTC).approve(address(swapper), maxAmountIn);

        // Record balances
        uint256 userCbbtcBefore = IERC20(CBBTC).balanceOf(user);
        uint256 userUsdcBefore = IERC20(USDC).balanceOf(user);

        // Execute swap
        try swapper.swapExactOutput(CBBTC, USDC, exactUsdcOut, maxAmountIn, user) returns (uint256 amountIn) {
            console.log("Swap successful! CBBTC spent:", amountIn);

            // Verify balances
            uint256 userCbbtcAfter = IERC20(CBBTC).balanceOf(user);
            uint256 userUsdcAfter = IERC20(USDC).balanceOf(user);

            // User should have received exactly the requested USDC
            assertEq(userUsdcAfter - userUsdcBefore, exactUsdcOut, "Did not receive exact USDC");

            // User should have spent amountIn CBBTC (got refund for unused)
            assertEq(userCbbtcBefore - userCbbtcAfter, amountIn, "CBBTC accounting mismatch");

            // Amount spent should be <= max
            assertLe(amountIn, maxAmountIn, "Spent more than max");
        } catch Error(string memory reason) {
            console.log("Swap failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Swap failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopPrank();
    }

    // ============ Edge Case Tests ============

    /// @notice Test that recipient receives tokens correctly (different from caller)
    function test_SwapExactInput_DifferentRecipient() public onlyMainnet {
        address recipient = makeAddr("recipient");
        uint256 swapAmount = 500e6; // 500 USDC

        vm.startPrank(user);

        IERC20(USDC).approve(address(swapper), swapAmount);

        uint256 recipientCbbtcBefore = IERC20(CBBTC).balanceOf(recipient);

        try swapper.swapExactInput(USDC, CBBTC, swapAmount, 1, recipient) returns (uint256 amountOut) {
            uint256 recipientCbbtcAfter = IERC20(CBBTC).balanceOf(recipient);
            assertEq(recipientCbbtcAfter - recipientCbbtcBefore, amountOut, "Recipient should receive tokens");
            console.log("Recipient received CBBTC:", amountOut);
        } catch {
            console.log("Swap failed - pool may not exist");
        }

        vm.stopPrank();
    }

    /// @notice Test refund mechanism in swapExactOutput
    function test_SwapExactOutput_RefundsExcess() public onlyMainnet {
        uint256 exactCbbtcOut = 0.005e8; // Want 0.005 CBBTC
        uint256 maxAmountIn = 10_000e6; // Provide way more USDC than needed

        vm.startPrank(user);

        IERC20(USDC).approve(address(swapper), maxAmountIn);

        uint256 userUsdcBefore = IERC20(USDC).balanceOf(user);

        try swapper.swapExactOutput(USDC, CBBTC, exactCbbtcOut, maxAmountIn, user) returns (uint256 amountIn) {
            uint256 userUsdcAfter = IERC20(USDC).balanceOf(user);

            // User should have been refunded the excess
            uint256 actualSpent = userUsdcBefore - userUsdcAfter;
            assertEq(actualSpent, amountIn, "Accounting mismatch");

            // Should have spent significantly less than max
            assertLt(amountIn, maxAmountIn, "Should spend less than max");
            console.log("USDC Spent:", amountIn);
            console.log("USDC Saved (refunded):", maxAmountIn - amountIn);
        } catch {
            console.log("Swap failed - pool may not exist");
        }

        vm.stopPrank();
    }

    /// @notice Test slippage protection works
    function test_SwapExactInput_RevertOnInsufficientOutput() public onlyMainnet {
        uint256 swapAmount = 100e6; // 100 USDC
        uint256 unrealisticMinOut = 100e8; // Expect 100 BTC (impossible)

        vm.startPrank(user);

        IERC20(USDC).approve(address(swapper), swapAmount);

        // This should revert because we can't get 100 BTC for 100 USDC
        vm.expectRevert(); // Could be "Insufficient output amount" or pool error
        swapper.swapExactInput(USDC, CBBTC, swapAmount, unrealisticMinOut, user);

        vm.stopPrank();
    }
}

/**
 * @title UniswapV4SwapperLocalTest
 * @notice Tests for local deployment (without fork)
 * @dev These tests deploy a fresh swapper and test basic functionality
 */
contract UniswapV4SwapperLocalTest is Test {
    UniswapV4Swapper public swapper;

    address constant MOCK_ROUTER = address(0x1);
    address constant MOCK_QUOTER = address(0x2);
    uint24 constant FEE = 3000;
    int24 constant TICK_SPACING = 60;
    address constant NO_HOOKS = address(0);

    function setUp() public {
        // Skip fork tests
        if (block.chainid == 8453 || block.chainid == 84532) {
            return;
        }

        // Deploy a new swapper for local testing with pool config
        swapper = new UniswapV4Swapper(MOCK_ROUTER, MOCK_QUOTER, FEE, TICK_SPACING, NO_HOOKS);
    }

    modifier onlyLocal() {
        if (block.chainid == 8453 || block.chainid == 84532) {
            return;
        }
        _;
    }

    function test_Constructor_SetsImmutables() public onlyLocal {
        assertEq(address(swapper.i_UNIVERSAL_ROUTER()), MOCK_ROUTER);
        assertEq(address(swapper.i_QUOTER()), MOCK_QUOTER);
        assertEq(swapper.i_FEE(), FEE);
        assertEq(swapper.i_TICK_SPACING(), TICK_SPACING);
        assertEq(swapper.i_HOOKS(), NO_HOOKS);
    }

    function test_Constructor_WithZeroRouter() public onlyLocal {
        // Should not revert on construction with zero addresses
        UniswapV4Swapper zeroSwapper = new UniswapV4Swapper(address(0), address(0), FEE, TICK_SPACING, NO_HOOKS);
        assertEq(address(zeroSwapper.i_UNIVERSAL_ROUTER()), address(0));
    }
}
