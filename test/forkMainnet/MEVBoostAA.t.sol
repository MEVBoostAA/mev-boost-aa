// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "../../contracts/interfaces/IEntryPoint.sol";
import {IMEVAccount} from "../../contracts/interfaces/IMEVAccount.sol";
import {UserOperation} from "../../contracts/interfaces/UserOperation.sol";
import {MEVUserOperation} from "../../contracts/libraries/MEVUserOperation.sol";
import {MEVPaymaster} from "../../contracts/MEVPaymaster.sol";
import {MEVAccount} from "../../contracts/MEVAccount.sol";
import {MEVAccountFactory} from "../../contracts/MEVAccountFactory.sol";

contract MEVBoostAATest is Test {
    using MEVUserOperation for UserOperation;
    using ECDSA for bytes32;
    address public constant entryPointAddr =
        0x0576a174D229E3cFA37253523E645A78A0C91B57;
    uint256 public constant chainId = 1; // mainnet
    uint256 public constant ownerPrivateKey = uint256(1);
    address public owner = vm.addr(ownerPrivateKey);
    IEntryPoint public constant entryPoint = IEntryPoint(entryPointAddr);
    MEVAccount public mevAccount;
    MEVAccountFactory public mevAcountFactory;
    MEVPaymaster public mevPaymaster;
    address public searcher = makeAddr("searcher");
    address public receiver = makeAddr("receiver");
    address public feeCollector = makeAddr("feeCollector");
    uint256 public constant salt = 1024;

    function setUp() public {
        _setUpMEVAccountFactory();
        _setUpMEVPayMaster();
        _setUpMEVAccount();
    }

    function _setUpMEVAccountFactory() internal {
        mevAcountFactory = new MEVAccountFactory(entryPoint);
    }

    function _setUpMEVPayMaster() internal {
        mevPaymaster = new MEVPaymaster(entryPoint);
        mevPaymaster.deposit{value: 100 ether}(searcher);
        uint256 deposit = mevPaymaster.getDeposit(searcher);
        assertEq(deposit, 100 ether);
    }

    function _setUpMEVAccount() internal {
        address expectedAccount = mevAcountFactory.getAddress(
            owner,
            address(mevPaymaster),
            salt
        );
        mevAccount = mevAcountFactory.createAccount(
            owner,
            address(mevPaymaster),
            salt
        );
        assertEq(expectedAccount, address(mevAccount));
        assertEq(mevAccount.owner(), owner);
        vm.deal(address(mevAccount), 100 ether);
        assertEq(address(mevAccount).balance, 100 ether);
    }

    function testSelfSponsoredExpiredMEVAccount() public {
        IMEVAccount.MEVConfig memory mevConfig = IMEVAccount.MEVConfig({
            minAmount: 10,
            selfSponsoredAfter: uint48(block.timestamp) // block.timestamp >= selfSponsoredAfter is valid
        });
        uint256 amount = 0;
        bytes memory callData = abi.encodeCall(
            MEVAccount.boostExecute,
            (mevConfig, receiver, amount, "")
        );

        UserOperation memory userOp = UserOperation({
            sender: address(mevAccount),
            nonce: 0,
            initCode: "",
            callData: callData,
            callGasLimit: 500000,
            verificationGasLimit: 500000,
            preVerificationGas: 60000,
            maxFeePerGas: 3000000000,
            maxPriorityFeePerGas: 1500000000,
            paymasterAndData: "",
            signature: ""
        });
        bytes32 boostUserOpHash = userOp.boostHash(entryPoint);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ownerPrivateKey,
            boostUserOpHash.toEthSignedMessageHash()
        );
        userOp.signature = abi.encodePacked(r, s, v);
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        uint256 balanceOfReceiver = receiver.balance;
        uint256 balanceOfFeeCollector = feeCollector.balance;
        uint256 balanceOfMEVAccount = address(mevAccount).balance;
        uint256 balanceOfEntryPoint = entryPointAddr.balance;
        entryPoint.handleOps(ops, payable(feeCollector));
        uint256 deltaOfReceiver = receiver.balance - balanceOfReceiver;
        uint256 delatOfFeeCollector = feeCollector.balance -
            balanceOfFeeCollector;
        uint256 deltaOfMEVAccount = balanceOfMEVAccount -
            address(mevAccount).balance;
        uint256 deltaOfEntryPoint = entryPointAddr.balance -
            balanceOfEntryPoint;
        assertEq(
            deltaOfReceiver + delatOfFeeCollector + deltaOfEntryPoint,
            deltaOfMEVAccount
        );
        uint256 mevAccountBalanceInEntryPoint = entryPoint.balanceOf(
            address(mevAccount)
        );
        assertEq(mevAccountBalanceInEntryPoint, deltaOfEntryPoint);
    }

    function testSearcherSponsoredMEVAccount() public {}
}
