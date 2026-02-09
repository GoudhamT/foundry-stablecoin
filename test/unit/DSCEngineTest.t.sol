//SPDX-License-Identifir:MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "test/Mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig helperConfig;
    address wETH;
    address ethPriceFeed;
    address btcPriceFeed;
    uint256 USER_STARTING_BALANCE = 100;
    address USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (ethPriceFeed, btcPriceFeed, wETH,,) = helperConfig.localNetworkConfig();
        // vm.deal(USER, USER_STARTING_BALANCE);
        ERC20Mock(wETH).mint(USER, 200 ether);
        vm.prank(USER);
        ERC20Mock(wETH).approve(address(engine), 200 ether);
    }

    ///////////////////////////////////
    ///////// constructor  ///////////
    //////////////////////////////////
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertIfTokenAndPriceFeedAddressesMisMaching() public {
        tokenAddresses.push(wETH);
        priceFeedAddresses.push(ethPriceFeed);
        priceFeedAddresses.push(btcPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAreNotSameCount.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////////////////////
    ////    Price Feed     /////////////
    /////////////////////////////////////
    function testGetUSDValue() public view {
        uint256 ethAmount = 10e18;
        uint256 expectedUSD = 20000e18;
        uint256 acutalUSD = engine.getUSDValue(wETH, ethAmount);
        assertEq(expectedUSD, acutalUSD);
    }

    function testgetTokenAmountForUSD() public view {
        uint256 USDAmount = 100e18;
        uint256 expectedWEI = 0.05 ether;
        uint256 actualWEI = engine.getTokenAmountForUSD(wETH, USDAmount);
        assertEq(expectedWEI, actualWEI);
    }

    //////////////////////////////////
    /////   Deposit Collateral    ////
    /////////////////////////////////
    modifier depositCollateral() {
        uint256 collateralAmount = 5 ether;
        vm.prank(USER);
        engine.depositCollateral(wETH, collateralAmount);
        _;
    }

    function testRevertForZeroAmountCollateral() public {
        uint256 collateralAmount = 0;
        vm.prank(USER);
        ERC20Mock(wETH).approve(address(engine), 200);
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__InvalidAmount.selector);
        engine.depositCollateral(wETH, collateralAmount);
    }

    function testRevertForInvalidTokenAddress() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, 10 ether);
        vm.prank(USER);
        uint256 collateralAmount = 10;
        vm.expectRevert(DSCEngine.DSCEngine__InvalidTokenAddress.selector);
        engine.depositCollateral(address(ranToken), collateralAmount);
    }

    function testDepositCollateralIsValidAmount() public depositCollateral {
        uint256 expectedMintedDSC = 0;
        uint256 expectedCollateralDeposited = 5 ether;
        (uint256 actualMintedDSC, uint256 amountInUSD) = engine.getAccountInformation(USER);
        uint256 actualTokenAmount = engine.getTokenAmountForUSD(wETH, amountInUSD);
        assertEq(expectedMintedDSC, actualMintedDSC);
        assertEq(expectedCollateralDeposited, actualTokenAmount);
    }
}
