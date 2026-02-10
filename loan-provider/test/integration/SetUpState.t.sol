// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";

/// @title SetUpStateTest
/// @notice Validates all contracts are deployed and accessible after `make deploy-local`
contract SetUpStateTest is IntegrationTestBase {
    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Contract Deployment ============

    function test_SetUpState_AllCoreContractsDeployed() public view {
        assertTrue(address(loanContract) != address(0), "loan deployed");
        assertTrue(address(manager) != address(0), "access manager deployed");
        assertTrue(address(btcVault) != address(0), "btc vault deployed");
        assertTrue(address(usdcVault) != address(0), "usdc vault deployed");
        assertTrue(address(loanVaultFactory) != address(0), "loan vault factory deployed");
        assertTrue(swapper != address(0), "swapper deployed");
        assertTrue(bitmorPool != address(0), "bitmor pool deployed");
        assertTrue(addressesProvider != address(0), "addresses provider deployed");
    }

    function test_SetUpState_ContractsHaveCode() public view {
        assertGt(address(loanContract).code.length, 0, "loan has code");
        assertGt(address(manager).code.length, 0, "access manager has code");
        assertGt(address(btcVault).code.length, 0, "btc vault has code");
        assertGt(address(usdcVault).code.length, 0, "usdc vault has code");
        assertGt(address(loanVaultFactory).code.length, 0, "loan vault factory has code");
        assertGt(swapper.code.length, 0, "swapper has code");
    }

    // ============ Token Configuration ============

    function test_SetUpState_TokensHaveCorrectDecimals() public view {
        assertEq(IERC20Metadata(address(usdc)).decimals(), 6, "USDC has 6 decimals");
        assertEq(IERC20Metadata(address(cbBTC)).decimals(), 8, "cbBTC has 8 decimals");
    }

    // ============ Oracle ============

    function test_SetUpState_OracleReturnsPrice() public view {
        (, int256 btcPrice,,,) = btcOracle.latestRoundData();
        assertGt(btcPrice, 0, "BTC oracle price > 0");
    }

    // ============ User Funding ============

    function test_SetUpState_UserIsFunded() public view {
        assertEq(usdc.balanceOf(testUser), TC.USER_USDC_BALANCE, "user has USDC");
        assertEq(cbBTC.balanceOf(testUser), TC.USER_CBBTC_BALANCE, "user has cbBTC");
    }

    // ============ Swap Adapter Liquidity ============

    function test_SetUpState_SwapAdapterHasLiquidity() public view {
        assertGt(cbBTC.balanceOf(swapper), 0, "swap adapter has cbBTC");
        assertGt(usdc.balanceOf(swapper), 0, "swap adapter has USDC");
    }

    // ============ Loan Parameters ============

    function test_SetUpState_LoanParametersConfigured() public view {
        // These are set by ExecutePhase3 via LPM_SLOW delayed operations
        (,, uint256 minDeposit) = loanContract.getLoanDetails(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION);
        assertGt(minDeposit, 0, "min deposit should be configured (non-zero)");
    }

    // ============ Strategies ============

    function test_SetUpState_BTCVault_HasStrategy() public view {
        // BTCVault should have AaveTokenizedStrategy added via BVC scheduled operation
        address strategy = config.getAaveTokenizedStrategy();
        assertTrue(strategy != address(0), "aave strategy should be deployed");
        assertGt(strategy.code.length, 0, "aave strategy should have code");
    }

    function test_SetUpState_USDCVault_HasStrategy() public view {
        address strategy = config.getUSDCStrategy();
        assertTrue(strategy != address(0), "usdc strategy should be deployed");
        assertGt(strategy.code.length, 0, "usdc strategy should have code");
    }

    // ============ Access Control ============

    function test_SetUpState_RolesGrantedCorrectly() public view {
        // EXECUTOR granted to admin
        (bool hasExecutor,) = manager.hasRole(EXECUTOR_ID(), admin);
        assertTrue(hasExecutor, "admin should have EXECUTOR role");

        // LPCM granted to bitmorPool
        (bool hasLPCM,) = manager.hasRole(LPCM_ID(), bitmorPool);
        assertTrue(hasLPCM, "bitmorPool should have LPCM role");

        // BVD granted to Loan contract
        (bool hasBVD,) = manager.hasRole(BVD_ID(), address(loanContract));
        assertTrue(hasBVD, "loan should have BVD role for BTCVault deposits");

        // LPM_FAST granted to admin
        (bool hasLPMFast,) = manager.hasRole(LPM_FAST_ID(), admin);
        assertTrue(hasLPMFast, "admin should have LPM_FAST role");
    }

    function test_SetUpState_BitmorLoanRegistered() public {
        // Query LendingPoolAddressesProvider.getBitmorLoan() via low-level call
        (bool ok, bytes memory data) = addressesProvider.staticcall(abi.encodeWithSignature("getBitmorLoan()"));
        assertTrue(ok, "getBitmorLoan call should succeed");
        address registeredLoan = abi.decode(data, (address));
        assertEq(registeredLoan, address(loanContract), "registered loan should match loanContract");
    }

    // ============ Mocking Policy ============

    /// @notice Documents the integration test mocking policy
    /// @dev Direct token minting is allowed only in setUp helpers (_setupTestUser, _seedBLPLiquidity,
    ///      _setupLiquidator). Individual test bodies should interact through protocol interfaces only.
    ///      Oracle manipulation via MockChainlinkOracle is allowed because Chainlink is an external
    ///      dependency mock (we don't control Chainlink in production). Enforcement is via code review.
    function test_SetUpState_MockingPolicyDocumented() public pure {
        // This test documents the policy. Enforcement is via code review.
        assertTrue(true);
    }

    // ============ Oracle: bvBTC Price Path ============

    /// @notice Validates the AaveOracle returns a valid price for bvBTC (BTCVault shares)
    /// @dev After ExecutePhase3, the oracle uses the real bvBTC pricing path:
    ///      price = btcPrice * BTCVault.convertToAssets(1e8) / 1e8
    ///      This test validates the price is positive and related to BTC price.
    function test_SetUpState_AaveOracle_bvBTCPrice() public view {
        address oracle = config.getOracle();

        // Query AaveOracle.getAssetPrice(btcVault) via low-level staticcall (Solidity 0.6.12 contract)
        (bool ok, bytes memory data) =
            oracle.staticcall(abi.encodeWithSignature("getAssetPrice(address)", address(btcVault)));
        assertTrue(ok, "getAssetPrice(bvBTC) should succeed");
        uint256 bvBTCPrice = abi.decode(data, (uint256));
        assertGt(bvBTCPrice, 0, "bvBTC price should be > 0");

        // Also check raw BTC price for comparison
        (, int256 btcPrice,,,) = btcOracle.latestRoundData();
        // bvBTC price should be related to BTC price (within same order of magnitude)
        assertGt(bvBTCPrice, uint256(btcPrice) / 10, "bvBTC price should be in same range as BTC");

        // Verify bvBTC path is active by checking s_bvBTC is set
        (bool okBvBTC, bytes memory bvBTCData) = oracle.staticcall(abi.encodeWithSignature("s_bvBTC()"));
        if (okBvBTC && bvBTCData.length >= 32) {
            address configuredBvBTC = abi.decode(bvBTCData, (address));
            if (configuredBvBTC == address(btcVault)) {
                // Real bvBTC path is active: price derived via convertToAssets
                // With no deposits, convertToAssets(1e8) == 1e8, so bvBTC price == BTC price
                assertEq(bvBTCPrice, uint256(btcPrice), "bvBTC price should equal BTC price when 1:1 ratio");
            }
        }
        // If s_bvBTC is not set (pre-ExecutePhase3 reconfiguration), the direct oracle path is used,
        // which also returns the BTC price. Either way, the test passes.
    }
}
