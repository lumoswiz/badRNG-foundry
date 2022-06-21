## Security Vulnerability: bad RNG
** The goal of this project was to find a security vulnerability in a smart contract, work out how to exploit it and then write tests to demonstrate whether the exploit was successful.

### Motivation

In an effort to learn Solidity, I have been:
- Playing around with [Foundry](https://github.com/foundry-rs/foundry), and working my way through the [book](https://book.getfoundry.sh/).
- Completing challenges from the Damn Vulnerable Defi Foundry edition found [here](https://github.com/nicolasgarcia214/damn-vulnerable-defi-foundry).
- Watching/reading the educational content of [Patrick Collins](https://twitter.com/PatrickAlphaC).

In Patrick's latest [video](https://www.youtube.com/watch?v=TmZ8gH-toX0) on auditing smart contracts, he challenged the audience to pause the video and try to find the vulnerability in several smart contracts in this [repo](https://github.com/PatrickAlphaC/hardhat-security-fcc/). So that's what I did, and this is my best attempt to exploit the [BadRNG.sol](https://github.com/PatrickAlphaC/hardhat-security-fcc/blob/main/contracts/BadRNG.sol) contract and produce tests written in Foundry using what I've managed to learn to date.

### Approach & Learnings
** How is a winner picked?
- `randomWinnerIndex` is determined from the `block.difficulty` (globally available variable) and `msg.sender`.
- Addresses that have entered the raffle are stored in a dynamic array `s_players`. The address of the winner is found from `randomWinnerIndex % s_players.length`.
- Since the array is private, we can't 'easily' access the length, but we still can do it. The way forward? Accessing data from storage slots. Familiar with the work of [noxx](https://twitter.com/noxx3xxon), I dove head first into EVM Deep Dives - Part 3 [here](https://noxx.substack.com/p/evm-deep-dives-the-path-to-shadowy-3ea?s=r), which led me [here](https://programtheblockchain.com/posts/2018/03/09/understanding-ethereum-smart-contract-storage/).

** What was my approach?
- We can know all of the variables we need to know when to enter the raffle, and when to call `pickWinner()` to end the raffle. So our [Attack.sol](./src/Attack.sol) contract should have a function to `enter()` the Raffle and one to `withdraw()` funds from the contract to our address.
- To create users, I created a Utilities contract that I saw utilised in the Damn Vulnerable Defi Foundry edition [here](https://github.com/nicolasgarcia214/damn-vulnerable-defi-foundry/blob/master/test/utils/Utilities.sol). This allowed me to use the `createUsers(uint256 numUsers)` function to create a desired number of users with a 100 ether starting balance in [BadRNGTest.sol](./test/BadRNG.t.sol) (my testing contract).
- The attacker address was set as `payable(address(0x69))` for the culture, starting with a 30 ether balance (achieved using the Foundry deal cheatcode). The Attack.sol contract was then deployed and funded with 12 ether by the attacker. I have used the Openzeppelin Ownable contract to ensure that the attacker is the owner of Attack.
- The length of `s_players` is stored at slot 0 of the BadRNG.sol contract, so the `testSlot()` function was used to check that this was true. This utilised a Foundry cheatcode `load` which loads the value from the storage slot of an account (*exactly what we need!*).
- With `forge test`, foundry allows you to set the block difficulty. I wanted to test that this was working as intend with the function `testBlockDifficulty()`. Decide on a block difficulty to test (e.g. 13000000), and then run:
```sh
forge test --block-difficulty 13000000 --match-test testBlockDifficulty
```
I have used a constant block difficulty value of 13000000 throughout all of my testing. Notably my `testAttack()` implementation is not flexible, so that changing the block difficulty will likely lead to a failed test. This can be improved in future implementations.
- The index of the winner was found by using the helper function `winnerIndex(uint256 length)`.
- I wanted to be able to retrieve an address in `s_players` at a given index location from storage. To achieve this, I utilised the helper functions `getSlotBytesRepresentation` and `retrieveAddressFromSlotIndex` where a bytes32 representation of the relevant slot was found and then used to retrieve the correct slot based on a desired index. 
- I tested that these functions were working as intended using the following tests: `testSlotIndexToRetrieveAddress` (based on 20 users) and `testFuzzSlotIndexToRetrieveAddress` (a fuzzed implementation with restrictions on the number of users and fuzz_runs=50 set in foundry.toml). To achieve the user restrictions, I used the `assume()` cheatcode from Foundry.
- Using the above tools, I wrote a (*rigid*) `testAttack()` function that enters the raffle certain index of `s_players`, waits until the array gets to a length that ensures a win in the raffle, then calls the `pickWinner()` function, finally calling `withdraw()` from the Attack contract. This test can be run with:
```sh
forge test --block-difficulty 13000000 --match-test testAttack -vvvvv
```
