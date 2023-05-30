// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMEVBoostPaymaster} from "./interfaces/IMEVBoostPaymaster.sol";
import {IPaymaster} from "./interfaces/IPaymaster.sol";
import {UserOperation} from "./interfaces/UserOperation.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {IMEVBoostAccount} from "./interfaces/IMEVBoostAccount.sol";
import {_packValidationData} from "./libraries/Helpers.sol";
import {MEVUserOperationLib} from "./libraries/MEVUserOperation.sol";
import {MEVPayInfoLib} from "./libraries/MEVPayInfo.sol";

contract MEVBoostPaymaster is ERC165, IMEVBoostPaymaster, Ownable {
    using ECDSA for bytes32;
    using MEVUserOperationLib for UserOperation;
    using MEVPayInfoLib for IMEVBoostPaymaster.MEVPayInfo;

    uint256 public constant SIG_VALIDATION_FAILED = 1;
    // must larger than real cost of postOP
    uint256 public constant MAX_GAS_OF_POST = 40000;
    string public constant EIP712_DOMAIN =
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    bytes32 public constant NAME_HASH = keccak256(bytes("MEVBoostPaymaster"));
    bytes32 public constant VERSION_HASH = keccak256(bytes("v0"));

    IEntryPoint public immutable entryPoint;
    bytes32 public immutable domainSeparator; // ERC-721

    uint256 public liability;
    mapping(address => uint256) public balances;

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
        domainSeparator = keccak256(
            abi.encode(
                keccak256(bytes(EIP712_DOMAIN)),
                NAME_HASH,
                VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    )
        external
        view
        override
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        return _validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    /// @inheritdoc IPaymaster
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external override onlyEntryPoint {
        _postOp(mode, context, actualGasCost);
    }

    function deposit(address provider) external payable {
        liability += msg.value;
        balances[provider] += msg.value;
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /**
     * add stake for this paymaster.
     * This method can also carry eth value to add to the current stake.
     * @param unstakeDelaySec - the unstake delay for this paymaster. Can only be increased.
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
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

    function getMEVPayInfo(
        address provider,
        bool requireSuccess,
        UserOperation calldata userOp
    )
        external
        view
        returns (
            IMEVBoostPaymaster.MEVPayInfo memory mevPayInfo,
            bool isMEVBoostUserOp
        )
    {
        bytes4 selector = bytes4(userOp.callData);
        uint256 minMEVAmount;
        if (
            selector == IMEVBoostAccount.boostExecuteBatch.selector ||
            selector == IMEVBoostAccount.boostExecute.selector
        ) {
            isMEVBoostUserOp = true;
            IMEVBoostAccount.MEVConfig memory mevConfig = abi.decode(
                userOp.callData[4:],
                (IMEVBoostAccount.MEVConfig)
            );
            minMEVAmount = mevConfig.minAmount;
        }

        mevPayInfo = IMEVBoostPaymaster.MEVPayInfo(
            provider,
            userOp.boostHash(entryPoint),
            minMEVAmount,
            requireSuccess
        );
    }

    function getBoostUserOpHash(
        UserOperation calldata userOp
    ) external view returns (bytes32 boostUserOpHash) {
        boostUserOpHash = userOp.boostHash(entryPoint);
    }

    function getMinMEVAmount(
        UserOperation calldata userOp
    ) external pure returns (uint256 minMEVAmount) {
        bytes4 selector = bytes4(userOp.callData);
        require(
            selector == IMEVBoostAccount.boostExecuteBatch.selector ||
                selector == IMEVBoostAccount.boostExecute.selector,
            "not a MEVBoostUserOp"
        );
        IMEVBoostAccount.MEVConfig memory mevConfig = abi.decode(
            userOp.callData[4:],
            (IMEVBoostAccount.MEVConfig)
        );
        minMEVAmount = mevConfig.minAmount;
    }

    function getDeposit(address provider) public view returns (uint256) {
        return balances[provider];
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165, ERC165) returns (bool) {
        return
            interfaceId == type(IMEVBoostPaymaster).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal view returns (bytes memory context, uint256 validationData) {
        require(
            userOp.verificationGasLimit > MAX_GAS_OF_POST,
            "DepositPaymaster: gas too low for postOp"
        );

        (
            IMEVBoostPaymaster.MEVPayInfo memory mevPayInfo,
            bytes memory signature
        ) = abi.decode(
                userOp.paymasterAndData[20:],
                (IMEVBoostPaymaster.MEVPayInfo, bytes)
            );
        require(
            mevPayInfo.boostUserOpHash == userOp.boostHash(entryPoint),
            "invalid mev info"
        );
        uint256 totalCost = maxCost + mevPayInfo.amount;
        require(
            balances[mevPayInfo.provider] >= totalCost,
            "provider balance not enough"
        );
        validationData = mevPayInfo.verify(domainSeparator, signature)
            ? 0
            : SIG_VALIDATION_FAILED;
        bytes4 selector = bytes4(userOp.callData);
        bool isBoostUserOp = mevPayInfo.amount > 0 &&
            (selector == IMEVBoostAccount.boostExecuteBatch.selector ||
                selector == IMEVBoostAccount.boostExecute.selector);
        if (isBoostUserOp) {
            IMEVBoostAccount.MEVConfig memory mevConfig = abi.decode(
                userOp.callData[4:],
                (IMEVBoostAccount.MEVConfig)
            );
            require(
                mevPayInfo.amount >= mevConfig.minAmount,
                "mev amount is not enough"
            );
            validationData = _packValidationData(
                validationData == SIG_VALIDATION_FAILED, // sigFailed
                mevConfig.selfSponsoredAfter, // validUntil
                0 // validAfter
            );
        }

        return (
            abi.encode(
                userOpHash,
                mevPayInfo,
                userOp.sender,
                isBoostUserOp,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas
            ),
            validationData
        );
    }

    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) internal {
        (
            bytes32 userOpHash,
            IMEVBoostPaymaster.MEVPayInfo memory mevPayInfo,
            address receiver,
            bool isBoostUserOp,
            uint256 maxFeePerGas,
            uint256 maxPriorityFeePerGas
        ) = abi.decode(
                context,
                (
                    bytes32,
                    IMEVBoostPaymaster.MEVPayInfo,
                    address,
                    bool,
                    uint256,
                    uint256
                )
            );
        uint256 gasPrice = _getGasPrice(maxFeePerGas, maxPriorityFeePerGas);
        uint256 feeAmount = actualGasCost + MAX_GAS_OF_POST * gasPrice;
        bool isUserOpSuccess = mode == IPaymaster.PostOpMode.opSucceeded;
        uint256 mevAmount = mevPayInfo.requireSuccess && !isUserOpSuccess
            ? 0 // only provide gas fee
            : mevPayInfo.amount; // provide gas fee and mev fee
        uint256 totalCost = mevAmount + feeAmount;
        balances[mevPayInfo.provider] -= totalCost;
        balances[receiver] += mevAmount;
        liability -= feeAmount;

        emit SettleUserOp(
            userOpHash,
            mevPayInfo.boostUserOpHash,
            mevPayInfo.provider,
            receiver,
            mevPayInfo.amount,
            mevAmount,
            totalCost,
            isBoostUserOp,
            isUserOpSuccess
        );
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
