// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {BaseAccount} from "./abstracts/BaseAccount.sol";
import {UserOperation} from "./interfaces/UserOperation.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {IAccount} from "./interfaces/IAccount.sol";
import {_packValidationData} from "./libraries/ValidationData.sol";
import {MEVUserOperation} from "./libraries/MEVUserOperation.sol";
import {IMEVAccount} from "./interfaces/IMEVAccount.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * minimal account.
 *  this is sample minimal account.
 *  has execute, eth handling methods
 *  has a single signer that can send requests through the entryPoint.
 */
contract MEVAccount is
    IMEVAccount,
    BaseAccount,
    UUPSUpgradeable,
    Initializable
{
    using ECDSA for bytes32;
    using MEVUserOperation for UserOperation;

    IEntryPoint private immutable _entryPoint;
    //filler member, to push the nonce and owner to the same slot
    // the "Initializeble" class takes 2 bytes in the first slot
    bytes28 private _filler;
    //explicit sizes of nonce, to fit a single storage cell with "owner"
    uint96 private _nonce;
    address public owner;
    address public mevPaymaster;

    event MEVAccountInitialized(
        IEntryPoint indexed entryPoint,
        address indexed owner,
        address indexed mevPaymaster
    );

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    modifier onlyEntryPointOrOwner() {
        require(
            msg.sender == address(entryPoint()) || msg.sender == owner,
            "account: not Owner or EntryPoint"
        );
        _;
    }

    /// @inheritdoc BaseAccount
    function nonce() public view virtual override returns (uint256) {
        return _nonce;
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
        returns (uint256 validationData)
    {
        _requireFromEntryPoint();
        bytes4 selector = bytes4(userOp.callData);
        if (
            selector == this.boostExecuteBatch.selector ||
            selector == this.boostExecute.selector
        ) {
            MEVConfig memory mevConfig = abi.decode(
                userOp.callData[4:],
                (MEVConfig)
            );
            bytes32 userBootOpHash = userOp.boostHash(entryPoint());
            validationData = _validateSignature(userOp, userBootOpHash);
            address paymaster = address(bytes20(userOp.paymasterAndData[:20]));
            if (validationData == 0 && paymaster != mevPaymaster) {
                validationData = _packValidationData(
                    false,
                    0,
                    mevConfig.selfSponsoredAfter
                );
            }
        } else {
            validationData = _validateSignature(userOp, userOpHash);
        }
        if (userOp.initCode.length == 0) {
            _validateAndUpdateNonce(userOp);
        }

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

    function supportsInterface(
        bytes4 interfaceId
    ) external view virtual returns (bool) {
        return interfaceId == type(IMEVAccount).interfaceId;
    }

    function initialize(
        address anOwner,
        address anMEVPaymaster
    ) public virtual initializer {
        _initialize(anOwner, anMEVPaymaster);
    }

    function _initialize(address anOwner, address anMEVPaymaster) internal {
        owner = anOwner;
        mevPaymaster = anMEVPaymaster;
        emit MEVAccountInitialized(entryPoint(), owner, mevPaymaster);
    }

    /// implement template method of BaseAccount
    function _validateAndUpdateNonce(
        UserOperation calldata userOp
    ) internal override {
        require(_nonce++ == userOp.nonce, "account: invalid nonce");
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
}
