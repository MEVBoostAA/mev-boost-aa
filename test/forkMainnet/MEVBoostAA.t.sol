// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "../../contracts/interfaces/IEntryPoint.sol";
import {UserOperation} from "../../contracts/interfaces/UserOperation.sol";
import {MEVUserOperation} from "../../contracts/libraries/MEVUserOperation.sol";
import {MEVBoostPaymaster} from "../../contracts/MEVBoostPaymaster.sol";
import {MEVBoostAccount} from "../../contracts/MEVBoostAccount.sol";
import {IMEVBoostAccount} from "../../contracts/interfaces/IMEVBoostAccount.sol";
import {MEVBoostAccountFactory} from "../../contracts/MEVBoostAccountFactory.sol";

contract MEVBoostAATest is Test {
    using MEVUserOperation for UserOperation;
    using ECDSA for bytes32;
    address public constant entryPointAddr =
        0x0576a174D229E3cFA37253523E645A78A0C91B57;
    uint256 public constant chainId = 1; // mainnet
    uint256 public constant ownerPrivateKey = uint256(1);
    address public owner = vm.addr(ownerPrivateKey);
    IEntryPoint public constant entryPoint = IEntryPoint(entryPointAddr);
    MEVBoostAccount public mevBoostAccount;
    MEVBoostAccountFactory public mevAcountFactory;
    MEVBoostPaymaster public mevBoostPaymaster;
    uint256 public constant searcherPrivateKey = uint256(2);
    address public searcher = vm.addr(searcherPrivateKey);
    address public receiver = makeAddr("receiver");
    address public feeCollector = makeAddr("feeCollector");
    uint256 public constant salt = 1024;

    function setUp() public {
        _setUpMEVBoostAccountFactory();
        _setUpMEVPayMaster();
        _setUpMEVBoostAccount();
    }

    function _setUpMEVBoostAccountFactory() internal {
        mevAcountFactory = new MEVBoostAccountFactory(entryPoint);
    }

    function _setUpMEVPayMaster() internal {
        mevBoostPaymaster = new MEVBoostPaymaster(entryPoint);
        mevBoostPaymaster.deposit{value: 100 ether}(searcher);
        uint256 deposit = mevBoostPaymaster.getDeposit(searcher);
        assertEq(deposit, 100 ether);
    }

    function _setUpMEVBoostAccount() internal {
        address expectedAccount = mevAcountFactory.getAddress(
            owner,
            address(mevBoostPaymaster),
            salt
        );
        mevBoostAccount = mevAcountFactory.createAccount(
            owner,
            address(mevBoostPaymaster),
            salt
        );
        assertEq(expectedAccount, address(mevBoostAccount));
        assertEq(mevBoostAccount.owner(), owner);
        vm.deal(address(mevBoostAccount), 100 ether);
        assertEq(address(mevBoostAccount).balance, 100 ether);
    }

    function testSelfSponsoredExpiredMEVBoostAccount() public {
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

    function testSearcherSponsoredMEVBoostAccount() public {
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
        uint256 balanceOfSearcher = mevBoostPaymaster.getDeposit(searcher);
        uint256 balanceOfReceiver = receiver.balance;
        uint256 balanceOfFeeCollector = feeCollector.balance;
        uint256 balanceOfMEVBoostAccount = address(mevBoostAccount).balance;
        uint256 mevOfMEVBoostAccount = mevBoostPaymaster.getDeposit(
            address(mevBoostAccount)
        );
        entryPoint.handleOps(ops, payable(feeCollector));
        uint256 deltaOfSearcher = balanceOfSearcher -
            mevBoostPaymaster.getDeposit(searcher);
        uint256 deltaOfReceiver = receiver.balance - balanceOfReceiver;
        uint256 delatOfFeeCollector = feeCollector.balance -
            balanceOfFeeCollector;
        uint256 deltaOfMEVBoostAccount = balanceOfMEVBoostAccount -
            address(mevBoostAccount).balance;
        uint256 deltaMEVOfMEVBoostAccount = mevBoostPaymaster.getDeposit(
            address(mevBoostAccount)
        ) - mevOfMEVBoostAccount;
        assertEq(deltaOfMEVBoostAccount, deltaOfReceiver);
        assertEq(deltaOfReceiver, transferAmount);
        assertEq(deltaMEVOfMEVBoostAccount, mevMinAmount);
        uint256 legacyAmount = entryPoint.balanceOf(
            address(mevBoostPaymaster)
        ) - mevBoostPaymaster.liability();
        assertEq(
            deltaOfSearcher,
            delatOfFeeCollector + deltaMEVOfMEVBoostAccount + legacyAmount
        );
    }

    function _handleOpsAndCheckForSelfSponsoredTx(
        UserOperation[] memory ops,
        uint256 transferAmount
    ) internal {
        uint256 balanceOfReceiver = receiver.balance;
        uint256 balanceOfFeeCollector = feeCollector.balance;
        uint256 balanceOfMEVBoostAccount = address(mevBoostAccount).balance;
        uint256 balanceOfEntryPoint = entryPointAddr.balance;
        entryPoint.handleOps(ops, payable(feeCollector));
        uint256 deltaOfReceiver = receiver.balance - balanceOfReceiver;
        uint256 delatOfFeeCollector = feeCollector.balance -
            balanceOfFeeCollector;
        uint256 deltaOfMEVBoostAccount = balanceOfMEVBoostAccount -
            address(mevBoostAccount).balance;
        uint256 deltaOfEntryPoint = entryPointAddr.balance -
            balanceOfEntryPoint;
        assertEq(deltaOfReceiver, transferAmount);
        assertEq(
            deltaOfReceiver + delatOfFeeCollector + deltaOfEntryPoint,
            deltaOfMEVBoostAccount
        );
        uint256 mevBoostAccountBalanceInEntryPoint = entryPoint.balanceOf(
            address(mevBoostAccount)
        );
        assertEq(mevBoostAccountBalanceInEntryPoint, deltaOfEntryPoint);
    }

    function _buildUserOp(
        uint256 _waitInterval,
        uint256 _mevMinAmount,
        uint256 _transferAmount
    ) internal view returns (UserOperation memory userOp) {
        IMEVBoostAccount.MEVConfig memory mevConfig = IMEVBoostAccount
            .MEVConfig({
                minAmount: _mevMinAmount,
                selfSponsoredAfter: uint48(block.timestamp + _waitInterval)
            });
        bytes memory callData = abi.encodeCall(
            IMEVBoostAccount.boostExecute,
            (mevConfig, receiver, _transferAmount, "")
        );

        userOp = UserOperation({
            sender: address(mevBoostAccount),
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
        MEVBoostPaymaster.MEVPayInfo memory payInfo = mevBoostPaymaster
            .getMEVPayInfo(searcher, userOp);

        bytes32 payInfoHash = mevBoostPaymaster.getMEVPayInfoHash(payInfo);
        payInfo.signature = _getSignature(payInfoHash, searcherPrivateKey);
        bytes memory paymasterAndData = abi.encodePacked(
            address(mevBoostPaymaster),
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
