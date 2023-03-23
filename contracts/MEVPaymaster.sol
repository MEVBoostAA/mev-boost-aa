// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMEVPaymaster} from "./interfaces/IMEVPaymaster.sol";
import {IPaymaster} from "./interfaces/IPaymaster.sol";
import {UserOperation} from "./interfaces/UserOperation.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {_packValidationData} from "./libraries/ValidationData.sol";
import {MEVUserOperation} from "./libraries/MEVUserOperation.sol";
import {IMEVAccount} from "./interfaces/IMEVAccount.sol";

contract MEVPaymaster is IMEVPaymaster, Ownable {
    using ECDSA for bytes32;
    using MEVUserOperation for UserOperation;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;
    uint256 public constant GAS_OF_POST = 35000;
    IEntryPoint public immutable entryPoint;
    mapping(address => uint256) balances;
    mapping(bytes32 => MEVInfo) mevMapping;

    struct MEVInfo {
        address provider;
        address receiver;
        uint256 amount;
        bool enable;
    }

    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
    }

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external override returns (bytes memory context, uint256 validationData) {
        _requireFromEntryPoint();
        return _validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal returns (bytes memory context, uint256 validationData) {
        require(
            userOp.verificationGasLimit > GAS_OF_POST,
            "DepositPaymaster: gas too low for postOp"
        );

        MEVPayInfo memory mevPayInfo = abi.decode(
            userOp.paymasterAndData[20:],
            (MEVPayInfo)
        );
        require(
            mevPayInfo.boostHash == userOp.boostHash(entryPoint),
            "invalid mev info"
        );
        uint256 totalCost = maxCost + mevPayInfo.amount;
        require(
            balances[mevPayInfo.provider] >= totalCost,
            "provider balance not enough"
        );
        balances[mevPayInfo.provider] -= totalCost;
        bytes32 mevPayInfoHash = _getMEVPayInfoHash(mevPayInfo);
        validationData = _validateSignature(mevPayInfo, mevPayInfoHash);
        bytes4 selector = bytes4(userOp.callData);
        if (
            mevPayInfo.amount > 0 &&
            (selector == IMEVAccount.boostExecuteBatch.selector ||
                selector == IMEVAccount.boostExecute.selector)
        ) {
            IMEVAccount.MEVConfig memory mevConfig = abi.decode(
                userOp.callData[4:],
                (IMEVAccount.MEVConfig)
            );
            require(
                mevPayInfo.amount >= mevConfig.minAmount,
                "mev amount is not enough"
            );
            if (validationData == 0) {
                validationData = _packValidationData(
                    false,
                    mevConfig.selfSponsoredAfter,
                    0
                );
            }
            mevMapping[userOpHash] = MEVInfo(
                mevPayInfo.provider,
                userOp.sender,
                mevPayInfo.amount,
                true
            );
            emit AddMEV(mevPayInfo.provider, userOp.sender, mevPayInfo.amount);
        }

        return (
            abi.encode(
                userOpHash,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                maxCost
            ),
            validationData
        );
    }

    /// @inheritdoc IPaymaster
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external override {
        _requireFromEntryPoint();
        _postOp(mode, context, actualGasCost);
    }

    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) internal {
        (
            bytes32 userOpHash,
            uint256 maxFeePerGas,
            uint256 maxPriorityFeePerGas,
            uint256 maxCost
        ) = abi.decode(context, (bytes32, uint256, uint256, uint256));
        uint256 gasPrice = _getGasPrice(maxFeePerGas, maxPriorityFeePerGas);
        uint256 totalCost = actualGasCost + GAS_OF_POST * gasPrice;
        MEVInfo memory mevInfo = mevMapping[userOpHash];
        balances[mevInfo.provider] += maxCost - totalCost;
        if (mevInfo.enable) {
            delete mevMapping[userOpHash];
            if (mode == IPaymaster.PostOpMode.opSucceeded) {
                balances[mevInfo.receiver] += mevInfo.amount;
                emit FetchMEV(
                    mevInfo.provider,
                    mevInfo.receiver,
                    mevInfo.amount
                );
            } else {
                balances[mevInfo.provider] += mevInfo.amount;
                emit RefundMEV(
                    mevInfo.provider,
                    mevInfo.receiver,
                    mevInfo.amount
                );
            }
        }
    }

    function getMEVPayInfo(
        address provider,
        UserOperation calldata userOp
    ) external view returns (MEVPayInfo memory mevPayInfo) {
        bytes4 selector = bytes4(userOp.callData);
        require(
            selector == IMEVAccount.boostExecuteBatch.selector ||
                selector == IMEVAccount.boostExecute.selector,
            "not a mev account"
        );
        IMEVAccount.MEVConfig memory mevConfig = abi.decode(
            userOp.callData[4:],
            (IMEVAccount.MEVConfig)
        );
        mevPayInfo = MEVPayInfo(
            provider,
            userOp.boostHash(entryPoint),
            mevConfig.minAmount,
            ""
        );
    }

    function getDeposit(address provider) external view returns (uint256) {
        return balances[provider];
    }

    function deposit(address provider) external payable {
        balances[provider] += msg.value;
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    function withdrawTo(
        address payable withdrawAddress,
        uint256 amount
    ) external {
        balances[msg.sender] -= amount;
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external view virtual returns (bool) {
        return interfaceId == type(IMEVPaymaster).interfaceId;
    }

    /**
     * add stake for this paymaster.
     * This method can also carry eth value to add to the current stake.
     * @param unstakeDelaySec - the unstake delay for this paymaster. Can only be increased.
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    /**
     * unlock the stake, in order to withdraw it.
     * The paymaster can't serve requests once unlocked, until it calls addStake again
     */
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /**
     * withdraw the entire paymaster's stake.
     * stake must be unlocked first (and then wait for the unstakeDelay to be over)
     * @param withdrawAddress the address to send withdrawn value.
     */
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
    }

    /// validate the call is made from a valid entrypoint
    function _requireFromEntryPoint() internal virtual {
        require(msg.sender == address(entryPoint), "Sender not EntryPoint");
    }

    function _internalMEVPayInfoHash(
        MEVPayInfo memory mevPayInfo
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    mevPayInfo.provider,
                    mevPayInfo.boostHash,
                    mevPayInfo.amount
                )
            );
    }

    function _getMEVPayInfoHash(
        MEVPayInfo memory mevPayInfo
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _internalMEVPayInfoHash(mevPayInfo),
                    address(this),
                    entryPoint,
                    block.chainid
                )
            );
    }

    /// implement template method of BaseAccount
    function _validateSignature(
        MEVPayInfo memory mevPayInfo,
        bytes32 mevPayInfoHash
    ) internal pure returns (uint256 validationData) {
        bytes32 hash = mevPayInfoHash.toEthSignedMessageHash();
        if (mevPayInfo.provider != hash.recover(mevPayInfo.signature))
            return SIG_VALIDATION_FAILED;
        return 0;
    }

    function _getGasPrice(
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas
    ) internal view returns (uint256) {
        if (maxFeePerGas == maxPriorityFeePerGas) {
            //legacy mode (for networks that don't support basefee opcode)
            return maxFeePerGas;
        }
        return _min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
