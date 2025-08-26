// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

/**
 * @title  SymmioPartyB Upgradeable
 * @notice Advanced upgradeable Party B implementation for the Symmio protocol with comprehensive
 *         access control, signature verification, and secure call execution capabilities.
 *         Supports role-based permissions, multicast operations, and EIP-1271 signature validation.
 *
 * @dev    Core features include:
 *         • Upgradeable contract architecture with proper initialization
 *         • Multi-level role-based access control for different operation types
 *         • Function selector restrictions for sensitive protocol operations
 *         • Multicast whitelist system for external contract interactions
 *         • EIP-1271 compliant signature verification for contract authentication
 *         • Comprehensive token management with approvals and withdrawals
 *         • Pause functionality for emergency controls
 *         • Reentrancy protection for all state-changing operations
 */

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

import { SignatureVerifier } from "./SignatureVerifier.sol";

interface ISymmio {
	function isCallFromInstantLayer() external view returns (bool);
}

contract SymmioPartyB is
	Initializable,
	SignatureVerifier,
	PausableUpgradeable,
	ReentrancyGuardUpgradeable,
	AccessControlEnumerableUpgradeable,
	IERC1271
{
	/* ─────────────────────────────── Roles ─────────────────────────────── */

	/// @notice Role for trusted operations, token approvals, and external contract calls.
	bytes32 public constant TRUSTED_ROLE = keccak256("TRUSTED_ROLE");

	/// @notice Role for managing restricted functions, multicast whitelist, and token withdrawals.
	bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

	/// @notice Role for updating contract configuration and signer settings.
	bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

	/// @notice Role that can pause contract operations.
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

	/// @notice Role that can unpause contract operations.
	bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

	/* ──────────────────────── Storage Variables ──────────────────────── */

	/// @notice Address of the core Symmio protocol contract for trading operations.
	address public symmioAddress;

	/// @notice Address of the authorized signer for EIP-1271 signature verification.
	address public signer;

	/// @notice Mapping of function selectors to their restriction status.
	/// @dev If true, only MANAGER_ROLE can call this function on Symmio.
	mapping(bytes4 => bool) public restrictedSelectors;

	/// @notice Mapping of addresses to their multicast whitelist status.
	/// @dev If true, the address can be a destination in multicast calls.
	mapping(address => bool) public multicastWhitelist;

	/* ─────────────────────────────── Events ─────────────────────────────── */

	/**
	 * @notice Emitted when the Symmio protocol address is updated.
	 * @param oldSymmioAddress Previous Symmio contract address.
	 * @param newSymmioAddress New Symmio contract address.
	 */
	event SetSymmioAddress(address oldSymmioAddress, address newSymmioAddress);

	/**
	 * @notice Emitted when a function selector's restriction status is changed.
	 * @param selector Function selector being modified.
	 * @param state    New restriction state (true = restricted to MANAGER_ROLE).
	 */
	event SetRestrictedSelector(bytes4 selector, bool state);

	/**
	 * @notice Emitted when an address's multicast whitelist status is changed.
	 * @param addr  Address being modified.
	 * @param state New whitelist state (true = whitelisted for multicast calls).
	 */
	event SetMulticastWhitelist(address addr, bool state);

	/* ─────────────────────────────── Errors ─────────────────────────────── */

	error InvalidTargetAddress(address self); // target address cannot be this contract
	error TokenNotApproved(address token, address spender, uint256 amount); // token approval failed
	error TokenNotTransferred(address token, address recipient, uint256 amount); // token transfer failed
	error ArrayLengthMismatch(uint256 destinationsLength, uint256 callDatasLength); // input arrays different lengths
	error InvalidAddress(address providedAddress); // address is zero or invalid
	error InvalidCallData(uint256 dataLength); // call data too short
	error InsufficientPermissions(address sender, bytes4 selector); // caller lacks required role
	error DestinationNotWhitelisted(address destination); // multicast destination not whitelisted

	/* ─────────────────────────── Initialization ─────────────────────────── */

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/**
	 * @notice Initialize the upgradeable SymmioPartyB contract.
	 * @param admin           Address receiving admin privileges and initial roles.
	 * @param symmioAddress_  Address of the core Symmio protocol contract.
	 *
	 * @dev Sets up initial roles and contract references. The admin receives
	 *      DEFAULT_ADMIN_ROLE and SETTER_ROLE for initial configuration.
	 */
	function initialize(address admin, address symmioAddress_) public initializer {
		__Pausable_init();
		__AccessControl_init();
		__ReentrancyGuard_init();

		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		_grantRole(SETTER_ROLE, admin);
		_grantRole(MANAGER_ROLE, admin); // for setting MulticastWhitelist
		symmioAddress = symmioAddress_;
	}

	/* ────────────────────────── Admin Functions ────────────────────────── */

	/**
	 * @notice Update the Symmio protocol contract address.
	 * @param addr New Symmio protocol address.
	 *
	 * @dev Only callable by accounts with DEFAULT_ADMIN_ROLE.
	 */
	function setSymmioAddress(address addr) external onlyRole(DEFAULT_ADMIN_ROLE) {
		emit SetSymmioAddress(symmioAddress, addr);
		symmioAddress = addr;
	}

	/**
	 * @notice Configure function selector access restrictions.
	 * @param selector Function selector to modify.
	 * @param state    True to restrict to MANAGER_ROLE only, false for normal access.
	 *
	 * @dev Only callable by accounts with DEFAULT_ADMIN_ROLE.
	 */
	function setRestrictedSelector(bytes4 selector, bool state) external onlyRole(DEFAULT_ADMIN_ROLE) {
		restrictedSelectors[selector] = state;
		emit SetRestrictedSelector(selector, state);
	}

	/**
	 * @notice Set the authorized signer for EIP-1271 signature verification.
	 * @param _signer Address of the new authorized signer.
	 *
	 * @dev Only callable by accounts with SETTER_ROLE.
	 */
	function setSigner(address _signer) external onlyRole(SETTER_ROLE) {
		signer = _signer;
	}

	/**
	 * @notice Manage the multicast whitelist for external contract calls.
	 * @param addr  Contract address to modify.
	 * @param state True to whitelist, false to remove from whitelist.
	 *
	 * @dev Only callable by accounts with MANAGER_ROLE. Cannot add this contract to whitelist.
	 */
	function setMulticastWhitelist(address addr, bool state) external onlyRole(MANAGER_ROLE) {
		if (addr == address(this)) revert InvalidTargetAddress(address(this));
		multicastWhitelist[addr] = state;
		emit SetMulticastWhitelist(addr, state);
	}

	/* ────────────────────── Token Management ────────────────────── */

	/**
	 * @notice Approve token spending by the Symmio protocol.
	 * @param token  ERC20 token address to approve.
	 * @param amount Approval amount.
	 *
	 * @dev Only callable by accounts with TRUSTED_ROLE when contract is not paused.
	 */
	function _approve(address token, uint256 amount) external onlyRole(TRUSTED_ROLE) whenNotPaused {
		bool success = IERC20Upgradeable(token).approve(symmioAddress, amount);
		if (!success) revert TokenNotApproved(token, symmioAddress, amount);
	}

	/**
	 * @notice Withdraw ERC20 tokens from the contract.
	 * @param token  ERC20 token address to withdraw.
	 * @param amount Amount of tokens to withdraw.
	 *
	 * @dev Only callable by accounts with MANAGER_ROLE. Tokens are sent to the caller.
	 */
	function withdrawERC20(address token, uint256 amount) external onlyRole(MANAGER_ROLE) {
		bool success = IERC20Upgradeable(token).transfer(msg.sender, amount);
		if (!success) revert TokenNotTransferred(token, msg.sender, amount);
	}

	/* ──────────────────── Call Execution Functions ──────────────────── */

	/**
	 * @notice Execute multiple calls to the Symmio protocol.
	 * @param _callDatas Array of encoded function call data.
	 *
	 * @dev Only executable when contract is not paused. Protected against reentrancy.
	 *      Access control is enforced per function selector basis.
	 */
	function _call(bytes[] calldata _callDatas) external whenNotPaused nonReentrant {
		for (uint8 i; i < _callDatas.length; i++) {
			_executeCall(symmioAddress, _callDatas[i]);
		}
	}

	/**
	 * @notice Execute multiple calls to different whitelisted contracts.
	 * @param destAddresses Array of target contract addresses.
	 * @param _callDatas    Array of encoded function call data.
	 *
	 * @dev Only executable when contract is not paused. All destination addresses
	 *      must be whitelisted. Requires TRUSTED_ROLE for external contract calls.
	 */
	function _multicastCall(address[] calldata destAddresses, bytes[] calldata _callDatas) external whenNotPaused nonReentrant {
		if (destAddresses.length != _callDatas.length) revert ArrayLengthMismatch(destAddresses.length, _callDatas.length);

		for (uint8 i; i < _callDatas.length; i++) {
			_executeCall(destAddresses[i], _callDatas[i]);
		}
	}

	/* ───────────────────────── Internal Helpers ───────────────────────── */

	/**
	 * @dev Execute a single contract call with comprehensive security checks.
	 * @param destAddress Target contract address.
	 * @param callData    Encoded function call data.
	 *
	 * @dev Performs access control based on target address and function selector.
	 *      For Symmio calls, checks both restricted selectors and general permissions.
	 *      For external calls, validates whitelist and requires TRUSTED_ROLE.
	 */
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
				if (!hasRole(MANAGER_ROLE, msg.sender) && !hasRole(TRUSTED_ROLE, msg.sender) && !ISymmio(symmioAddress).isCallFromInstantLayer())
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

	/* ───────────────────────── Pause Control ───────────────────────── */

	/**
	 * @notice Pause all contract operations except view functions.
	 * @dev Only callable by accounts with PAUSER_ROLE.
	 */
	function pause() external onlyRole(PAUSER_ROLE) {
		_pause();
	}

	/**
	 * @notice Resume all contract operations.
	 * @dev Only callable by accounts with UNPAUSER_ROLE.
	 */
	function unpause() external onlyRole(UNPAUSER_ROLE) {
		_unpause();
	}

	/* ──────────────────── ERC-1271 Implementation ──────────────────── */

	/**
	 * @notice Verify signature validity using ERC-1271 standard for contract-based authentication.
	 * @param hash      Hash of the data that was signed.
	 * @param signature Signature bytes to verify.
	 * @return magicValue Magic value (0x1626ba7e) if signature is valid, 0xffffffff otherwise.
	 *
	 * @dev Delegates signature verification to the SignatureVerifier base contract
	 *      using the configured signer address for validation.
	 */
	function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
		return isValidSignatureEIP1271(signer, hash, signature);
	}
}
