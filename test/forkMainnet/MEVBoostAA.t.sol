// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {IEntryPoint} from "../../contracts/interfaces/IEntryPoint.sol";
import {MEVPaymaster} from "../../contracts/MEVPaymaster.sol";
import {MEVAccount} from "../../contracts/MEVAccount.sol";
import {MEVAccountFactory} from "../../contracts/MEVAccountFactory.sol";

contract MEVBoostAATest is Test {
    address public constant entryPointAddr =
        0x0576a174D229E3cFA37253523E645A78A0C91B57;
    uint256 public constant chainId = 1; // mainnet
    uint256 public constant userPrivateKey = uint256(1);
    address public userAddress = vm.addr(userPrivateKey);
    IEntryPoint public constant entryPoint = IEntryPoint(entryPointAddr);
    MEVAccount public mevAccount;
    MEVAccountFactory public mevAcountFactory;
    MEVPaymaster public mevPaymaster;
    address public searcher = makeAddr("searcher");

    function setUp() public {
        _setUpMEVPayMaster();
    }

    function _setUpMEVPayMaster() internal {
        mevPaymaster = new MEVPaymaster(entryPoint);
        mevPaymaster.deposit{value: 100 ether}(searcher);
        uint256 deposit = mevPaymaster.getDeposit(searcher);
        assertEq(deposit, 100 ether);
    }

    function _setUpMEVAccount() internal {}

    function testSelfSponsoredMEVAccount() public {}
}
