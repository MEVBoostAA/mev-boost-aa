// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "../../contracts/interfaces/IEntryPoint.sol";
import {UserOperation} from "../../contracts/interfaces/UserOperation.sol";
import {MEVUserOperation} from "../../contracts/libraries/MEVUserOperation.sol";
import {MEVPaymaster} from "../../contracts/MEVPaymaster.sol";
import {MEVAccount} from "../../contracts/MEVAccount.sol";
import {IMEVAccount} from "../../contracts/interfaces/IMEVAccount.sol";
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
    uint256 public constant searcherPrivateKey = uint256(2);
    address public searcher = vm.addr(searcherPrivateKey);
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
        uint256 waitInterval = 0;
        uint256 mevMinAmount = 10;
        uint256 amount = 1 ether;
        UserOperation memory userOp = _buildUserOp(
            waitInterval,
            mevMinAmount,
            amount
        );
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;
        _handleOpsAndCheckForSelfSponsoredTx(ops, amount);
    }

    function testSearcherSponsoredMEVAccount() public {
        uint256 waitInterval = 1000;
        uint256 mevMinAmount = 10;
        uint256 amount = 1 ether;
        UserOperation memory userOp = _buildUserOp(
            waitInterval,
            mevMinAmount,
            amount
        );
        // paymaster can provide mev to make tx valid
        _attachPaymasterAndData(userOp);
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;
        _handleOpsAndCheckForSearcherSponsoredTx(ops, mevMinAmount, amount);
    }

    function _handleOpsAndCheckForSearcherSponsoredTx(
        UserOperation[] memory ops,
        uint256 mevMinAmount,
        uint256 transferAmount
    ) internal {
        uint256 balanceOfSearcher = mevPaymaster.getDeposit(searcher);
        uint256 balanceOfReceiver = receiver.balance;
        uint256 balanceOfFeeCollector = feeCollector.balance;
        uint256 balanceOfMEVAccount = address(mevAccount).balance;
        uint256 mevOfMEVAccount = mevPaymaster.getDeposit(address(mevAccount));
        entryPoint.handleOps(ops, payable(feeCollector));
        uint256 deltaOfSearcher = balanceOfSearcher -
            mevPaymaster.getDeposit(searcher);
        uint256 deltaOfReceiver = receiver.balance - balanceOfReceiver;
        uint256 delatOfFeeCollector = feeCollector.balance -
            balanceOfFeeCollector;
        uint256 deltaOfMEVAccount = balanceOfMEVAccount -
            address(mevAccount).balance;
        uint256 deltaMEVOfMEVAccount = mevPaymaster.getDeposit(
            address(mevAccount)
        ) - mevOfMEVAccount;
        assertEq(deltaOfMEVAccount, deltaOfReceiver);
        assertEq(deltaOfReceiver, transferAmount);
        assertEq(deltaMEVOfMEVAccount, mevMinAmount);
        uint256 legacyAmount = entryPoint.balanceOf(address(mevPaymaster)) -
            mevPaymaster.liability();
        assertEq(
            deltaOfSearcher,
            delatOfFeeCollector + deltaMEVOfMEVAccount + legacyAmount
        );
    }

    function _handleOpsAndCheckForSelfSponsoredTx(
        UserOperation[] memory ops,
        uint256 transferAmount
    ) internal {
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
        assertEq(deltaOfReceiver, transferAmount);
        assertEq(
            deltaOfReceiver + delatOfFeeCollector + deltaOfEntryPoint,
            deltaOfMEVAccount
        );
        uint256 mevAccountBalanceInEntryPoint = entryPoint.balanceOf(
            address(mevAccount)
        );
        assertEq(mevAccountBalanceInEntryPoint, deltaOfEntryPoint);
    }

    function _buildUserOp(
        uint256 _waitInterval,
        uint256 _mevMinAmount,
        uint256 _transferAmount
    ) internal view returns (UserOperation memory userOp) {
        IMEVAccount.MEVConfig memory mevConfig = IMEVAccount.MEVConfig({
            minAmount: _mevMinAmount,
            selfSponsoredAfter: uint48(block.timestamp + _waitInterval)
        });
        bytes memory callData = abi.encodeCall(
            IMEVAccount.boostExecute,
            (mevConfig, receiver, _transferAmount, "")
        );

        userOp = UserOperation({
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
        userOp.signature = _getSignature(boostUserOpHash, ownerPrivateKey);
    }

    function _attachPaymasterAndData(
        UserOperation memory userOp
    ) internal view {
        // use min mev amount
        MEVPaymaster.MEVPayInfo memory payInfo = mevPaymaster.getMEVPayInfo(
            searcher,
            userOp
        );

        bytes32 payInfoHash = mevPaymaster.getMEVPayInfoHash(payInfo);
        payInfo.signature = _getSignature(payInfoHash, searcherPrivateKey);
        bytes memory paymasterAndData = abi.encodePacked(
            address(mevPaymaster),
            abi.encode(payInfo)
        );
        userOp.paymasterAndData = paymasterAndData;
    }

    function _getSignature(
        bytes32 _hash,
        uint256 _privateKey
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _privateKey,
            _hash.toEthSignedMessageHash()
        );
        return abi.encodePacked(r, s, v);
    }
}
