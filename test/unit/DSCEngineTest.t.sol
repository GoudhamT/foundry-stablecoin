//SPDX-License-Identifir:MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig helperConfig;
    address wETH;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (,, wETH,,) = helperConfig.localNetworkConfig();
    }

    function testGetUSDValue() public view {
        uint256 ethAmount = 10e18;
        uint256 expectedUSD = 20000e18;
        uint256 acutalUSD = engine.getUSDValue(wETH, ethAmount);
        assertEq(expectedUSD, acutalUSD);
    }
}
