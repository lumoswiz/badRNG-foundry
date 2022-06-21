// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {BadRNG} from "./BadRNG.sol";

contract Attack is Ownable {
    BadRNG badRNG;

    constructor(BadRNG _badRNG) payable {
        badRNG = _badRNG;
    }

    function enter() external onlyOwner {
        (bool success, ) = address(badRNG).call{value: 10 ether}(
            abi.encodeWithSignature("enterRaffle()")
        );
        require(success, "raffle_not_entered");
    }

    function withdraw() external payable onlyOwner {
        (bool withdraw_success, ) = msg.sender.call{
            value: address(this).balance
        }("");
        require(withdraw_success, "withdrawal_unsuccessful");
    }

    receive() external payable {}
}
