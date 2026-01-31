// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
contract DSCEngine {
    function depositColletralAndMintDSC() external {}

    function depositCollateral() external {}

    function redeemCollateralDSC() external {}

    function redeemcollateral() external {}

    function mintDSC() external {}

    function burnDSC() external {}

    //$100 ETH -> $50 DSC -> ETH goes down to $40 - under collateral
    // set threshold when collateral goes down
    function liquidate() external {}

    function GetHealthFactor() external view {}
}
