// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {BaseAccount} from "./abstracts/BaseAccount.sol";
import {UserOperation} from "./interfaces/UserOperation.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {IAccount} from "./interfaces/IAccount.sol";
import {_packValidationData} from "./libraries/Helpers.sol";
import {MEVUserOperation} from "./libraries/MEVUserOperation.sol";
import {IMEVBoostAccount} from "./interfaces/IMEVBoostAccount.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * minimal account.
 *  this is sample minimal account.
 *  has execute, eth handling methods
 *  has a single signer that can send requests through the entryPoint.
 */
contract MEVBoostAccount is
    IMEVBoostAccount,
    BaseAccount,
    UUPSUpgradeable,
    Initializable
{
    using ECDSA for bytes32;
    using MEVUserOperation for UserOperation;

    IEntryPoint private immutable _entryPoint;
    address public owner;
    address public mevBoostPaymaster;

    event MEVBoostAccountInitialized(
        IEntryPoint indexed entryPoint,
        address indexed owner,
        address indexed mevBoostPaymaster
    );

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    modifier onlyEntryPoint() {
        require(msg.sender == address(_entryPoint), "Sender not EntryPoint");
        _;
    }

    modifier onlyEntryPointOrOwner() {
        require(
            msg.sender == address(_entryPoint) || msg.sender == owner,
            "account: not Owner or EntryPoint"
        );
        _;
    }

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    constructor(IEntryPoint anEntryPoint) {
        _entryPoint = anEntryPoint;
        _disableInitializers();
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    )
        external
        virtual
        override(IAccount, BaseAccount)
        onlyEntryPoint
        returns (uint256 validationData)
    {
        bytes4 selector = bytes4(userOp.callData);
        if (
            selector == this.boostExecuteBatch.selector ||
            selector == this.boostExecute.selector
        ) {
            MEVConfig memory mevConfig = abi.decode(
                userOp.callData[4:],
                (MEVConfig)
            );
            bytes32 userBootOpHash = userOp.boostHash(_entryPoint);
            validationData = _validateSignature(userOp, userBootOpHash);
            if (validationData == 0 && !_isMevPaymaster(userOp)) {
                validationData = _packValidationData(
                    false,
                    0,
                    mevConfig.selfSponsoredAfter
                );
            }
        } else {
            validationData = _validateSignature(userOp, userOpHash);
        }
        _validateNonce(userOp.nonce);
        _payPrefund(missingAccountFunds);
    }

    function execute(
        address dest,
        uint256 value,
        bytes calldata func
    ) external onlyEntryPointOrOwner {
        _call(dest, value, func);
    }

    function executeBatch(
        address[] calldata dest,
        uint256[] calldata value,
        bytes[] calldata func
    ) external onlyEntryPointOrOwner {
        _callBatch(dest, value, func);
    }

    function boostExecuteBatch(
        MEVConfig calldata mevConfig,
        address[] calldata dest,
        uint256[] calldata value,
        bytes[] calldata func
    ) external onlyEntryPointOrOwner {
        (mevConfig);
        _callBatch(dest, value, func);
    }

    function boostExecute(
        MEVConfig calldata mevConfig,
        address dest,
        uint256 value,
        bytes calldata func
    ) external onlyEntryPointOrOwner {
        (mevConfig);
        _call(dest, value, func);
    }

    function getBoostHash(
        UserOperation calldata userOp
    ) public view returns (bytes32) {
        return userOp.boostHash(_entryPoint);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external view virtual returns (bool) {
        return interfaceId == type(IMEVBoostAccount).interfaceId;
    }

    function initialize(
        address anOwner,
        address anMEVBoostPaymaster
    ) public virtual initializer {
        _initialize(anOwner, anMEVBoostPaymaster);
    }

    function _initialize(
        address anOwner,
        address anMEVBoostPaymaster
    ) internal {
        owner = anOwner;
        mevBoostPaymaster = anMEVBoostPaymaster;
        emit MEVBoostAccountInitialized(_entryPoint, owner, mevBoostPaymaster);
    }

    /// implement template method of BaseAccount
    function _validateSignature(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal virtual override returns (uint256 validationData) {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        if (owner != hash.recover(userOp.signature))
            return SIG_VALIDATION_FAILED;
        return 0;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal view override {
        (newImplementation);
        _onlyOwner();
    }

    function _onlyOwner() internal view {
        //directly from EOA owner, or through the account itself (which gets redirected through execute())
        require(
            msg.sender == owner || msg.sender == address(this),
            "only owner"
        );
    }

    function _call(
        address target,
        uint256 value,
        bytes calldata data
    ) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function _callBatch(
        address[] calldata dest,
        uint256[] calldata value,
        bytes[] calldata func
    ) internal {
        require(
            dest.length == func.length && dest.length == value.length,
            "wrong array lengths"
        );
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

    function _isMevPaymaster(
        UserOperation calldata userOp
    ) internal view returns (bool) {
        return
            userOp.paymasterAndData.length >= 20 &&
            address(bytes20(userOp.paymasterAndData[:20])) == mevBoostPaymaster;
    }
}
