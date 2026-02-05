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
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
    error DSCEngine__BreaksHealthFacor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__CollateralAmountMoreThanBalance();
    ///////////////////////////
    //    State Variables   //
    //////////////////////////
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUDATION_THRESHOLD = 50;
    uint256 private constant LIQUDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address tokenAddress => address priceFeedAddress) private s_priceFeed;
    mapping(address _sender => mapping(address _tokenAddress => uint256 _amount)) private s_UserCollateralDeposit;
    DecentralizedStableCoin private immutable i_dscAddress;
    mapping(address user => uint256 DSCmint) private s_DSCMinted;
    address[] private s_collateralTokens;
    ///////////////////////////
    //    Events   //
    //////////////////////////
    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed tokenAddress, uint256 indexed amount);
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
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        i_dscAddress = DecentralizedStableCoin(_dscAddress);
    }

    ///////////////////////////
    //   External Functions  //
    ///////////////////////////
    /*
     *@param: tokenCollateralAddress - address of ERC20 to deposit as collateral
     * @param: amountToCollateral - amount to deposit as collateral
     * @param: amountToMintDSc: amount to mint DSC token
     * @notice: this is single function which combines both deposit collateral and mint corresponding DSC
     */
    function depositColletralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountToCollateral,
        uint256 amountToMintDSc
    ) external {
        depositCollateral(tokenCollateralAddress, amountToCollateral);
        mintDSC(amountToMintDSc);
    }

    function redeemCollateralDSC() external {}

    function redeemcollateral(address tokenCollateralAddress, uint256 amountToCollateral)
        external
        moreThanZero(amountToCollateral)
        nonReentrant
    {
        //throw error if amount to be collateral more than then have
        uint256 amountBalance = s_UserCollateralDeposit[msg.sender][tokenCollateralAddress];
        if (amountToCollateral > amountBalance) {
            revert DSCEngine__CollateralAmountMoreThanBalance();
        }
        s_UserCollateralDeposit[msg.sender][tokenCollateralAddress] -= amountToCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountToCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountToCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHEalthFactorIsBroken(msg.sender);
        // we have a problem here, collateral is redeemed and DSC minted is not returned, which breaks health factor
        // 100$ ETH - 20 $ DSC
        // 100$ ETH - collateral redeemed -> no DSC burned
        // so first burn minted DSC then redeem collateral
    }

    // do we need to check if this breaks health factor?
    function burnDSC(uint256 amount) external moreThanZero(amount) nonReentrant {
        s_DSCMinted[msg.sender] -= amount;
        // incase if there is failure, revert happens from transferfrom , still getting bool is to make 100%
        bool success = i_dscAddress.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dscAddress.burn(amount);
        _revertIfHEalthFactorIsBroken(msg.sender); // I don;t think this is needed
    }

    //$100 ETH -> $50 DSC -> ETH goes down to $40 - under collateral
    // set threshold when collateral goes down
    function liquidate() external {}

    function GetHealthFactor() external view {}

    //////////////////////////////////////////
    //   Public Functions  //
    //////////////////////////////////////////
    /*
         * @param: tokenCollateralAddress - ERC20 token address to deposit as collateral
         * @param: _amountCollateral - how much amount to deposit for collateral
         * function follows CEI - Check Executes and Interactions
         */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedTokenCollateralAddress(_tokenCollateralAddress)
        nonReentrant
    {
        s_UserCollateralDeposit[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);

        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
        * @notice follows CEI
        * @notice _amntDSC - How much DSC user  wants to mint
        * @notice they must have more collateral than DSC to mint
        */
    function mintDSC(uint256 _amntDSC) public moreThanZero(_amntDSC) nonReentrant {
        s_DSCMinted[msg.sender] += _amntDSC;
        _revertIfHEalthFactorIsBroken(msg.sender);
        bool minted = i_dscAddress.mint(msg.sender, _amntDSC);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    //////////////////////////////////////////
    //   Private & Internal view Functions  //
    //////////////////////////////////////////
    /**
     * Returns how close liquidation is
     * if user get below 1 then they can get liquidated
     *
     */

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralInUSD = getCollateralInUSD(user);
        return (totalDSCMinted, collateralInUSD);
    }

    function _getHealthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral VALUE
        (uint256 totalDSCMinted, uint256 totalCollateralInUSD) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (totalCollateralInUSD * LIQUDATION_THRESHOLD) / LIQUDATION_PRECISION;
        // $1000 ETH * 50 = 500000 / 100 = 500

        //$150 ETH / 100 = 1.5
        //$ 150 * 50 = 7500 / 100 = 75  = > 75 / 100 which is leass than 1
        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    function _revertIfHEalthFactorIsBroken(address user) internal view {
        // 1. check health factor (they don't have collateral )
        // 2. revert if they don't
        uint256 userHealthFactor = _getHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFacor(userHealthFactor);
        }
    }

    //////////////////////////////////////////
    //   Public & External view Functions  //
    //////////////////////////////////////////
    function getCollateralInUSD(address user) public view returns (uint256 totalCollateralValueInUSD) {
        //Loop through collateral token and get amount mapped to token
        // get equivalent USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_UserCollateralDeposit[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256 collateralAmountinUSD) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //getting decimals
        uint256 feed_decimals = priceFeed.decimals();
        uint256 adjustedPrice = uint256(price) * (10 ** (18 - feed_decimals));
        //1 EHT = $1000
        //value from CL is 1000 * 1e8
        // collateralAmountinUSD = ((uint256(price) * ADDITIONAL_PRECISION) * amount) / PRECISION;
        collateralAmountinUSD = (adjustedPrice * amount) / PRECISION;
        return collateralAmountinUSD;
    }
}
