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

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title Decentralized StableCoin
 * @author Goudham T
 * collateral Exogeneous(ETH & BTC)
 * Minting Algorthmic
 * Relative Stability : pegged to USD
 * @dev This is contract ment to governed by DSCEngine, This contract is ERC20 implementation
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    /*Errors */
    error DecentralizedStableCoin__AmountCannotBeZero();
    error DecentralizedStableCoin__AmountExceedsBalance();
    error DecentralizedStableCoin__InvalidAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountCannotBeZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__AmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) public onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__InvalidAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountCannotBeZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
