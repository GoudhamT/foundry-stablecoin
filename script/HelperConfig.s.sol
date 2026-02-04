//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;
import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/Mocks/ MockV3Aggregator.sol";
import {ERC20Mock} from "test/Mocks/ERC20Mock.sol";

abstract contract codeConstants {
    uint8 public constant V3_DECIMALS = 8;
    int256 public constant V3_ETH_ANSWER = 2000e8;
    int256 public constant V3_BTC_ANSWER = 1000e8;
    string public constant ERC20_ETH_NAME = "WETH";
    string public constant ERC20_BTC_NAME = "WBTC";
    uint256 public constant ERC20_ETH_AMOUNT = 1000e8;
    uint256 public constant ERC20_BTC_AMOUNT = 1000e8;
    uint256 public constant SEPOLIA_CHAIN = 11155111;
    uint256 public constant ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
}

contract HelperConfig is Script, codeConstants {
    struct NetworkConfig {
        address wethUSDPriceFeedAddress;
        address wbtcUSDPriceFeedAddress;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public localNetworkConfig;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN) {
            localNetworkConfig = getSepoliaConfig();
        } else {
            localNetworkConfig = createorGetAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUSDPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUSDPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function createorGetAnvilConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.wbtcUSDPriceFeedAddress != address(0)) {
            return localNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator wethUSDFeed = new MockV3Aggregator(V3_DECIMALS, V3_ETH_ANSWER);
        ERC20Mock wethERC20 = new ERC20Mock(ERC20_ETH_NAME, ERC20_ETH_NAME, msg.sender, ERC20_ETH_AMOUNT);
        MockV3Aggregator wbtcUSDFeed = new MockV3Aggregator(V3_DECIMALS, V3_BTC_ANSWER);
        ERC20Mock wbtcERC20 = new ERC20Mock(ERC20_BTC_NAME, ERC20_BTC_NAME, msg.sender, ERC20_BTC_AMOUNT);
        vm.stopBroadcast();

        return NetworkConfig({
            wethUSDPriceFeedAddress: address(wethUSDFeed),
            wbtcUSDPriceFeedAddress: address(wbtcUSDFeed),
            weth: address(wethERC20),
            wbtc: address(wbtcERC20),
            deployerKey: ANVIL_KEY
        });
    }
}
