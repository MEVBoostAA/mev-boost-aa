// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {UserOperation} from "./interfaces/UserOperation.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {IAccount} from "./interfaces/IAccount.sol";
import {IMEVBoostAccount} from "./interfaces/IMEVBoostAccount.sol";
import {_packValidationData} from "./libraries/Helpers.sol";
import {MEVUserOperationLib} from "./libraries/MEVUserOperation.sol";
import {BaseAccount} from "./abstracts/BaseAccount.sol";
import {TokenCallbackHandler} from "./callback/TokenCallbackHandler.sol";

/**
 * minimal account.
 *  this is sample minimal account.
 *  has execute, eth handling methods
 *  has a single signer that can send requests through the entryPoint.
 */
contract MEVBoostAccount is
    IERC1271,
    ERC165,
    IMEVBoostAccount,
    BaseAccount,
    TokenCallbackHandler,
    UUPSUpgradeable,
    Initializable
{
    using ECDSA for bytes32;
    using MEVUserOperationLib for UserOperation;

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

    constructor(IEntryPoint anEntryPoint) {
        _entryPoint = anEntryPoint;
        _disableInitializers();
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

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
            IMEVBoostAccount.MEVConfig memory mevConfig = abi.decode(
                userOp.callData[4:],
                (IMEVBoostAccount.MEVConfig)
            );
            bytes32 userBootOpHash = userOp.boostHash(_entryPoint);
            validationData = _validateSignature(userOp, userBootOpHash);
            if (!_isMevPaymaster(userOp)) {
                validationData = _packValidationData(
                    validationData == SIG_VALIDATION_FAILED, // sigFailed
                    0, // validUntil
                    mevConfig.selfSponsoredAfter // validAfter
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
        bytes calldata data
    ) external onlyEntryPointOrOwner {
        _call(dest, value, data);
    }

    function executeBatch(
        address[] calldata dest,
        uint256[] calldata value,
        bytes[] calldata data
    ) external onlyEntryPointOrOwner {
        _callBatch(dest, value, data);
    }

    function boostExecuteBatch(
        IMEVBoostAccount.MEVConfig calldata mevConfig,
        address[] calldata dest,
        uint256[] calldata value,
        bytes[] calldata data
    ) external onlyEntryPointOrOwner {
        (mevConfig);
        _callBatch(dest, value, data);
    }

    function boostExecute(
        IMEVBoostAccount.MEVConfig calldata mevConfig,
        address dest,
        uint256 value,
        bytes calldata data
    ) external onlyEntryPointOrOwner {
        (mevConfig);
        _call(dest, value, data);
    }

    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view returns (bytes4 magicValue) {
        if (owner.code.length > 0) {
            return IERC1271(owner).isValidSignature(hash, signature);
        }
        if (owner == hash.recover(signature)) {
            return IERC1271.isValidSignature.selector; // EIP1271_MAGIC_VALUE
        }
        return 0xffffffff;
    }

    function initialize(
        address anOwner,
        address anMEVBoostPaymaster
    ) public virtual initializer {
        _initialize(anOwner, anMEVBoostPaymaster);
    }

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    function getBoostUserOpHash(
        UserOperation calldata userOp
    ) public view returns (bytes32) {
        return userOp.boostHash(_entryPoint);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(IERC165, ERC165, TokenCallbackHandler)
        returns (bool)
    {
        return
            (interfaceId == type(IERC1271).interfaceId ||
                interfaceId == type(IMEVBoostAccount).interfaceId) ||
            super.supportsInterface(interfaceId);
    }

    function _initialize(
        address anOwner,
        address anMEVBoostPaymaster
    ) internal {
        owner = anOwner;
        mevBoostPaymaster = anMEVBoostPaymaster;
        emit MEVBoostAccountInitialized(_entryPoint, owner, mevBoostPaymaster);
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
        bytes[] calldata data
    ) internal {
        require(
            dest.length == data.length && dest.length == value.length,
            "wrong array lengths"
        );
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, data[i]);
        }
    }

    /// implement template method of BaseAccount
    function _validateSignature(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal virtual override returns (uint256 validationData) {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        if (owner.code.length > 0) {
            return
                IERC1271(owner).isValidSignature(hash, userOp.signature) ==
                    IERC1271.isValidSignature.selector
                    ? 0
                    : SIG_VALIDATION_FAILED;
        }
        return
            owner == hash.recover(userOp.signature) ? 0 : SIG_VALIDATION_FAILED;
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

    function _isMevPaymaster(
        UserOperation calldata userOp
    ) internal view returns (bool) {
        return
            userOp.paymasterAndData.length >= 20 &&
            address(bytes20(userOp.paymasterAndData[:20])) == mevBoostPaymaster;
    }
}
