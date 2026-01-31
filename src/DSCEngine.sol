// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title : DSC Engine
 * @author : Goudham
 * The system is designed to be as minimal as possible and have token maintain $1 == 1$ peg
 * This stablecoin has properties:
 * Exogeneous collateral
 * Pegged
 * Algorithmically stable
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////////////
    //    Errors             //
    //////////////////////////
    error DSCEngine__InvalidAmount();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAreNotSameCount();
    error DSCEngine__InvalidTokenAddress();
    error DSCEngine__TransferFailed();
    ///////////////////////////
    //    State Variables   //
    //////////////////////////
    mapping(address tokenAddress => address priceFeedAddress) private s_priceFeed;
    mapping(address _sender => mapping(address _tokenAddress => uint256 _amount)) private s_UserCollataeralDeposit;
    DecentralizedStableCoin private immutable i_dscAddress;

    ///////////////////////////
    //    Events   //
    //////////////////////////
    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);

    ///////////////////////////
    //    Modifiers          //
    //////////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__InvalidAmount();
        }
        _;
    }
    modifier isAllowedTokenCollateralAddress(address _collateral) {
        if (s_priceFeed[_collateral] == address(0)) {
            revert DSCEngine__InvalidTokenAddress();
        }
        _;
    }

    ///////////////////////////
    //   constructor  //
    ///////////////////////////
    constructor(address[] memory _tokenAddresses, address[] memory _priceFeedAddresses, address _dscAddress) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAreNotSameCount();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeed[_tokenAddresses[i]] = _priceFeedAddresses[i];
        }
        i_dscAddress = DecentralizedStableCoin(_dscAddress);
    }

    ///////////////////////////
    //   External Functions  //
    ///////////////////////////
    function depositColletralAndMintDSC() external {}

    /*
     * @param: tokenCollateralAddress - ERC20 token address to deposit as collateral
     * @param: _amountCollateral - how much amount to deposit for collateral
     * function follows CEI - Check Executes and Interactions
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        external
        moreThanZero(_amountCollateral)
        isAllowedTokenCollateralAddress(_tokenCollateralAddress)
        nonReentrant
    {
        s_UserCollataeralDeposit[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);

        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralDSC() external {}

    function redeemcollateral() external {}

    function mintDSC() external {}

    function burnDSC() external {}

    //$100 ETH -> $50 DSC -> ETH goes down to $40 - under collateral
    // set threshold when collateral goes down
    function liquidate() external {}

    function GetHealthFactor() external view {}
}
