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
    error DSCEngine__HealthFactorIsOk();
    error DSCEngine__HealthFactorNotImproved();
    ///////////////////////////
    //    State Variables   //
    //////////////////////////
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address tokenAddress => address priceFeedAddress) private s_priceFeed;
    mapping(address _sender => mapping(address _tokenAddress => uint256 _amount)) private s_UserCollateralDeposit;
    DecentralizedStableCoin private immutable i_dscAddress;
    mapping(address user => uint256 DSCmint) private s_DSCMinted;
    address[] private s_collateralTokens;
    ///////////////////////////
    //    Events   //
    //////////////////////////
    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed tokenAddress, uint256 amount
    );
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

    /*
     *
     * @param tokenCollateralAddress  - ERC20 token address
     * @param collateralAmount  - amount to be collateral
     * @param amountToBurn  - amount of token to burn
     * @notice : this function does not require _checkHealthFacor  - as reedeem collateral is executing the same
     */
    function redeemCollateralDSC(address tokenCollateralAddress, uint256 collateralAmount, uint256 amountToBurn)
        external
    {
        burnDSC(amountToBurn);
        redeemcollateral(tokenCollateralAddress, collateralAmount);
    }

    function redeemcollateral(address tokenCollateralAddress, uint256 amountToCollateral)
        public
        moreThanZero(amountToCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountToCollateral);
        _revertIfHEalthFactorIsBroken(msg.sender);
        // we have a problem here, collateral is redeemed and DSC minted is not returned, which breaks health factor
        // 100$ ETH - 20 $ DSC
        // 100$ ETH - collateral redeemed -> no DSC burned
        // so first burn minted DSC then redeem collateral
    }

    // do we need to check if this breaks health factor?
    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(msg.sender, amount, msg.sender);
        _revertIfHEalthFactorIsBroken(msg.sender); // I don;t think this is needed
    }

    // $100 ETH -backing -> 50$ DSC
    // price goes down to $20 -> DSC isn;t worth $1!!!

    // $75 backing $50 DSC
    // liquidator takes $75 backing nad burns off $50 DSC
    //if someone is under collateralized, we will pay you to remove them
    /*
     * @param collateral - ERC20 address to liquidate from user
     * @param user - The user who broke health factor, it's value should be always above MIN_HEALTH_FACTOR
     * @param debtToCover  - Amount of DSC you want to burn to improve healthfactor
     * @notice you can partially liquidate user
     * @notice : you will get liuidation bonus for taking user funds
     * @notice function assumes working the protocol will be roughly 200% overcollateralized in order for this work
     * @notice : A known bug would be if  protocol is 100% or less undercollateralized, then we won't be able to incentify liquidators
     * for example: if price of collateral plummed before anyone liquidate
     * Follows CEI - Checks, Effects, Interactions
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // first check user health factor, if above min then liquidate is not required
        uint256 usersHealthFactorBefore = _getHealthFactor(user);
        if (usersHealthFactorBefore >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsOk();
        }
        // we want to burn DSC and collateral
        //example: $150 ETH -> $100 DSC
        // debt to cover : $100
        // $100 DSC = how much ETH??
        uint256 tokenAmountFromDebtCovered = getTokenAmountForUSD(collateral, debtToCover);
        uint256 collateralBonus = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeem = tokenAmountFromDebtCovered + collateralBonus;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralRedeem);
        _burnDSC(user, debtToCover, msg.sender);
        uint256 userHealthFactorAfter = _getHealthFactor(user);
        if (userHealthFactorAfter < usersHealthFactorBefore) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHEalthFactorIsBroken(msg.sender);
    }

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
     * @dev : call _redeemCollateral only when you have a heathfactor check
     *
     */
    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountToCollateral)
        private
    {
        //throw error if amount to be collateral more than then have
        uint256 amountBalance = s_UserCollateralDeposit[from][tokenCollateralAddress];
        if (amountToCollateral > amountBalance) {
            revert DSCEngine__CollateralAmountMoreThanBalance();
        }
        s_UserCollateralDeposit[from][tokenCollateralAddress] -= amountToCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountToCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountToCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
     *
     * @notice : call _burnDSc only when you have a health factor check
     * @param : onBehalfOf - user whose healthfacor is not good and trying to liquidate
     * @param : dscFrom  - user who is executing liquidate and sending hos DSC token to redeem collateral
     */
    function _burnDSC(address onBehalfOf, uint256 amountToBurn, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountToBurn;
        // incase if there is failure, revert happens from transferfrom , still getting bool is to make 100%
        bool success = i_dscAddress.transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dscAddress.burn(amountToBurn);
    }
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
        uint256 collateralAdjustedForThreshold = (totalCollateralInUSD * LIQUDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // $1000 ETH * 50 = 50000 / 100 = 500

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
    function getTokenAmountForUSD(address collateral, uint256 debtToCover) public view returns (uint256) {
        //get price feed address
        address feed = s_priceFeed[collateral];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 feed_decimals = priceFeed.decimals();
        uint256 updatedPrice = uint256(price) * (10 ** (18 - feed_decimals));
        // without precision : debt to cover = 10e18 -> pricesFeed 1ETH = $2000 so 2000e18 -> 10e18 / 2000e18 -> 18 cancels so 10/2000 -> 1/200 -> 0.005
        // which solidity cannot return 0.005 it gives 0, to avoid multiply nominator by 1e18
        return ((debtToCover * PRECISION) / updatedPrice);
    }

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
