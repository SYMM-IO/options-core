// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

import { SignatureVerifier } from "./SignatureVerifier.sol";

/// @title SymmioPartyB Contract
/// @notice Manages Party B operations in the Symmio protocol with role-based access control
contract SymmioPartyB is
	Initializable,
	SignatureVerifier,
	PausableUpgradeable,
	ReentrancyGuardUpgradeable,
	AccessControlEnumerableUpgradeable,
	IERC1271
{
	// ==================== CUSTOM ERRORS ====================
	error InvalidTargetAddress(address self);
	error TokenNotApproved(address token, address spender, uint256 amount);
	error TokenNotTransferred(address token, address recipient, uint256 amount);
	error ArrayLengthMismatch(uint256 destinationsLength, uint256 callDatasLength);
	error InvalidAddress(address providedAddress);
	error InvalidCallData(uint256 dataLength);
	error InsufficientPermissions(address sender, bytes4 selector);
	error DestinationNotWhitelisted(address destination);

	// ==================== ROLE DEFINITIONS ====================

	bytes32 public constant TRUSTED_ROLE = keccak256("TRUSTED_ROLE");
	bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
	bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

	// ==================== STATE VARIABLES ====================

	/// @notice Address of the Symmio protocol contract
	address public symmioAddress;

	/// @notice Address of the authorized signer for EIP-1271 signature verification
	address public signer;

	/// @notice Mapping of function selectors to their restriction status
	/// @dev If true, only MANAGER_ROLE can call this function
	mapping(bytes4 => bool) public restrictedSelectors;

	/// @notice Mapping of addresses to their multicast whitelist status
	/// @dev If true, the address can be a destination in multicast calls
	mapping(address => bool) public multicastWhitelist;

	// ==================== EVENTS ====================

	/// @notice Emitted when the Symmio address is updated
	/// @param oldSymmioAddress Previous Symmio address
	/// @param newSymmioAddress New Symmio address
	event SetSymmioAddress(address oldSymmioAddress, address newSymmioAddress);

	/// @notice Emitted when a selector's restriction status is changed
	/// @param selector The function selector
	/// @param state New restriction state
	event SetRestrictedSelector(bytes4 selector, bool state);

	/// @notice Emitted when an address's multicast whitelist status is changed
	/// @param addr The affected address
	/// @param state New whitelist state
	event SetMulticastWhitelist(address addr, bool state);

	// ==================== CONSTRUCTOR & INITIALIZER ====================

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/// @notice Initializes the contract
	/// @dev Sets up initial roles and contract references
	/// @param admin Address receiving admin privileges
	/// @param symmioAddress_ Address of the Symmio protocol contract
	function initialize(address admin, address symmioAddress_) public initializer {
		__Pausable_init();
		__AccessControl_init();
		__ReentrancyGuard_init();

		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		_grantRole(SETTER_ROLE, admin);
		symmioAddress = symmioAddress_;
	}

	// ==================== ADMIN FUNCTIONS ====================

	// Removed setSelectorsQuoteOffsets function (was used for sequenced calls)

	/// @notice Updates the Symmio protocol address
	/// @dev Can only be called by admin
	/// @param addr New protocol address
	function setSymmioAddress(address addr) external onlyRole(DEFAULT_ADMIN_ROLE) {
		emit SetSymmioAddress(symmioAddress, addr);
		symmioAddress = addr;
	}

	/// @notice Sets selector restrictions
	/// @dev Can only be called by admin
	/// @param selector Function selector to modify
	/// @param state New restriction state
	function setRestrictedSelector(bytes4 selector, bool state) external onlyRole(DEFAULT_ADMIN_ROLE) {
		restrictedSelectors[selector] = state;
		emit SetRestrictedSelector(selector, state);
	}

	/// @notice Sets signer for EIP-1271 signature verification
	/// @dev Can only be called by accounts with SETTER_ROLE
	/// @param _signer Address of the new signer
	function setSigner(address _signer) external onlyRole(SETTER_ROLE) {
		signer = _signer;
	}

	/// @notice Manages multicast whitelist
	/// @dev Can only be called by accounts with MANAGER_ROLE
	/// @param addr Contract address to modify
	/// @param state New whitelist state
	function setMulticastWhitelist(address addr, bool state) external onlyRole(MANAGER_ROLE) {
		if (addr == address(this)) revert InvalidTargetAddress(address(this));
		multicastWhitelist[addr] = state;
		emit SetMulticastWhitelist(addr, state);
	}

	// ==================== TOKEN MANAGEMENT ====================

	/// @notice Approves token spending by Symmio protocol
	/// @dev Can only be called by accounts with TRUSTED_ROLE when not paused
	/// @param token ERC20 token address
	/// @param amount Approval amount
	function _approve(address token, uint256 amount) external onlyRole(TRUSTED_ROLE) whenNotPaused {
		bool success = IERC20Upgradeable(token).approve(symmioAddress, amount);
		if (!success) revert TokenNotApproved(token, symmioAddress, amount);
	}

	/// @notice Withdraws ERC20 tokens from the contract
	/// @dev Can only be called by accounts with MANAGER_ROLE
	/// @param token ERC20 token address
	/// @param amount Amount to withdraw
	function withdrawERC20(address token, uint256 amount) external onlyRole(MANAGER_ROLE) {
		bool success = IERC20Upgradeable(token).transfer(msg.sender, amount);
		if (!success) revert TokenNotTransferred(token, msg.sender, amount);
	}

	// ==================== CALL EXECUTION FUNCTIONS ====================

	/// @notice Executes multiple calls to Symmio protocol
	/// @dev Can only be called when not paused and prevents reentrancy
	/// @param _callDatas Array of function call data
	function _call(bytes[] calldata _callDatas) external whenNotPaused nonReentrant {
		for (uint8 i; i < _callDatas.length; i++) {
			_executeCall(symmioAddress, _callDatas[i]);
		}
	}

	/// @notice Executes multiple calls to different contracts
	/// @dev Can only be called when not paused and prevents reentrancy
	/// @param destAddresses Array of target addresses
	/// @param _callDatas Array of function call data
	function _multicastCall(address[] calldata destAddresses, bytes[] calldata _callDatas) external whenNotPaused nonReentrant {
		if (destAddresses.length != _callDatas.length) revert ArrayLengthMismatch(destAddresses.length, _callDatas.length);

		for (uint8 i; i < _callDatas.length; i++) {
			_executeCall(destAddresses[i], _callDatas[i]);
		}
	}

	// Removed sequencedCall function

	// ==================== INTERNAL FUNCTIONS ====================

	/// @dev Executes a single contract call with security checks
	/// @param destAddress Target contract address
	/// @param callData Function call data
	function _executeCall(address destAddress, bytes memory callData) internal {
		if (destAddress == address(0)) revert InvalidAddress(destAddress);
		if (callData.length < 4) revert InvalidCallData(callData.length);

		if (destAddress == symmioAddress) {
			bytes4 functionSelector;
			// Extract the function selector from callData
			assembly {
				functionSelector := mload(add(callData, 0x20))
			}

			if (restrictedSelectors[functionSelector]) {
				_checkRole(MANAGER_ROLE, msg.sender);
			} else {
				if (!hasRole(MANAGER_ROLE, msg.sender) && !hasRole(TRUSTED_ROLE, msg.sender))
					revert InsufficientPermissions(msg.sender, functionSelector);
			}
		} else {
			if (!multicastWhitelist[destAddress]) revert DestinationNotWhitelisted(destAddress);
			_checkRole(TRUSTED_ROLE, msg.sender);
		}

		(bool _success, bytes memory _resultData) = destAddress.call{ value: 0 }(callData);
		if (!_success) {
			assembly {
				revert(add(_resultData, 32), mload(_resultData))
			}
		}
	}

	// ==================== PAUSE CONTROL ====================

	/// @notice Pauses contract operations
	/// @dev Can only be called by accounts with PAUSER_ROLE
	function pause() external onlyRole(PAUSER_ROLE) {
		_pause();
	}

	/// @notice Resumes contract operations
	/// @dev Can only be called by accounts with UNPAUSER_ROLE
	function unpause() external onlyRole(UNPAUSER_ROLE) {
		_unpause();
	}

	// ==================== EIP-1271 IMPLEMENTATION ====================

	/// @notice Verifies that the signer is the owner of the signing contract
	/// @dev Implements EIP-1271 `isValidSignature` standard for contract-based signature validation
	/// @param hash The hash of the data signed
	/// @param signature The signature generated by the signer
	/// @return magicValue A magic value (0x1626ba7e) if the signature is valid, 0xffffffff otherwise
	function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
		return isValidSignatureEIP1271(signer, hash, signature);
	}
}
