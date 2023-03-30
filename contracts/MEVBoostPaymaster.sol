// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMEVBoostPaymaster} from "./interfaces/IMEVBoostPaymaster.sol";
import {IPaymaster} from "./interfaces/IPaymaster.sol";
import {UserOperation} from "./interfaces/UserOperation.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {_packValidationData} from "./libraries/ValidationData.sol";
import {MEVUserOperation} from "./libraries/MEVUserOperation.sol";
import {IMEVBoostAccount} from "./interfaces/IMEVBoostAccount.sol";

contract MEVBoostPaymaster is IMEVBoostPaymaster, Ownable {
    using ECDSA for bytes32;
    using MEVUserOperation for UserOperation;
    uint256 private constant SIG_VALIDATION_FAILED = 1;
    // must larger than real cost of postOP
    uint256 public constant MAX_GAS_OF_POST = 35000;
    uint256 public liability;
    IEntryPoint public immutable entryPoint;
    mapping(address => uint256) balances;
    mapping(bytes32 => MEVInfo) mevMapping;

    struct MEVInfo {
        address provider;
        address receiver;
        uint256 amount;
        bool enable;
    }

    modifier onlyEntryPoint() {
        require(msg.sender == address(entryPoint), "Sender not EntryPoint");
        _;
    }

    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
    }

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    )
        external
        override
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        return _validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal returns (bytes memory context, uint256 validationData) {
        require(
            userOp.verificationGasLimit > MAX_GAS_OF_POST,
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
        bytes32 mevPayInfoHash = getMEVPayInfoHash(mevPayInfo);
        validationData = _validateSignature(mevPayInfo, mevPayInfoHash);
        bytes4 selector = bytes4(userOp.callData);
        if (
            mevPayInfo.amount > 0 &&
            (selector == IMEVBoostAccount.boostExecuteBatch.selector ||
                selector == IMEVBoostAccount.boostExecute.selector)
        ) {
            IMEVBoostAccount.MEVConfig memory mevConfig = abi.decode(
                userOp.callData[4:],
                (IMEVBoostAccount.MEVConfig)
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
    ) external override onlyEntryPoint {
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
        uint256 totalCost = actualGasCost + MAX_GAS_OF_POST * gasPrice;
        MEVInfo memory mevInfo = mevMapping[userOpHash];
        liability -= totalCost;
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
            selector == IMEVBoostAccount.boostExecuteBatch.selector ||
                selector == IMEVBoostAccount.boostExecute.selector,
            "not a mev account"
        );
        IMEVBoostAccount.MEVConfig memory mevConfig = abi.decode(
            userOp.callData[4:],
            (IMEVBoostAccount.MEVConfig)
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
        liability += msg.value;
        balances[provider] += msg.value;
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    function withdrawTo(
        address payable withdrawAddress,
        uint256 amount
    ) external {
        liability -= amount;
        balances[msg.sender] -= amount;
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    function fetchLegacy() external onlyOwner returns (uint256 legacy) {
        uint256 asset = entryPoint.balanceOf(address(this));
        require(asset > liability, "asset should greater than liability");
        legacy = asset - liability;
        liability = asset;
        balances[owner()] += legacy;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external view virtual returns (bool) {
        return interfaceId == type(IMEVBoostPaymaster).interfaceId;
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

    function getMEVPayInfoHash(
        MEVPayInfo memory mevPayInfo
    ) public view returns (bytes32) {
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
