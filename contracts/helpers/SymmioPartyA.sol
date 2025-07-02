// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

/**
 * @title  SymmioPartyA
 * @notice Account implementation for the Symmio platform representing Party A entities.
 *         Each instance serves as a managed trading account with delegated execution
 *         capabilities and ERC-1271 signature validation for contract-based authentication.
 *
 * @dev    Core features include:
 *         • ERC-1271 compliant signature validation for contract-based authentication
 *         • Secure function call delegation to the Symmio protocol
 *         • Integration with MultiAccount ownership verification
 */

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import { IMultiAccount } from "../interfaces/IMultiAccount.sol";
import { ISymmioPartyA } from "../interfaces/ISymmioPartyA.sol";

contract SymmioPartyA is AccessControl, IERC1271, ISymmioPartyA {
	/* ──────────────────────── Storage Variables ──────────────────────── */

	/// @notice Address of the core Symmio protocol contract for trading operations.
	address public symmioAddress;

	/// @notice Address of the MultiAccount contract that manages this Party A account.
	address public multiAccountAddress;

	/* ─────────────────────────────── Events ─────────────────────────────── */

	/**
	 * @notice Emitted when the Symmio protocol address is updated.
	 * @param oldSymmioContractAddress Previous Symmio contract address.
	 * @param newSymmioContractAddress New Symmio contract address.
	 */
	event SetSymmioAddress(address oldSymmioContractAddress, address newSymmioContractAddress);

	/* ─────────────────────────────── Errors ─────────────────────────────── */

	error OnlyMultiAccount(address sender, address expectedMultiAccount); // unauthorized access attempt

	/* ─────────────────────────── Initialization ─────────────────────────── */

	/**
	 * @notice Initialize the SymmioPartyA account with required contract addresses.
	 * @param multiAccountAddress_ Address of the MultiAccount contract managing this account.
	 * @param symmioAddress_       Address of the core Symmio protocol contract.
	 *
	 * @dev Grants DEFAULT_ADMIN_ROLE to the MultiAccount contract for configuration management.
	 */
	constructor(address multiAccountAddress_, address symmioAddress_) {
		_grantRole(DEFAULT_ADMIN_ROLE, multiAccountAddress_);
		symmioAddress = symmioAddress_;
		multiAccountAddress = multiAccountAddress_;
	}

	/* ────────────────────────── Admin Functions ────────────────────────── */

	/**
	 * @notice Update the address of the Symmio protocol contract.
	 * @param symmioAddress_ New address of the Symmio protocol contract.
	 *
	 * @dev Only callable by accounts with DEFAULT_ADMIN_ROLE (typically MultiAccount).
	 */
	function setSymmioAddress(address symmioAddress_) external onlyRole(DEFAULT_ADMIN_ROLE) {
		emit SetSymmioAddress(symmioAddress, symmioAddress_);
		symmioAddress = symmioAddress_;
	}

	/* ───────────────────── MultiAccount Functions ───────────────────── */

	/**
	 * @notice Execute a function call on the Symmio protocol contract.
	 * @param callData Encoded function call data to execute on Symmio.
	 * @return success    Whether the call execution was successful.
	 * @return resultData Return data from the Symmio function call.
	 *
	 * @dev Only callable by the designated MultiAccount contract. Provides
	 *      secure delegation of Symmio protocol interactions.
	 */
	function call(bytes memory callData) external onlyMultiAccount(msg.sender) returns (bool success, bytes memory resultData) {
		return symmioAddress.call{ value: 0 }(callData);
	}

	/* ──────────────────── ERC-1271 Implementation ──────────────────── */

	/**
	 * @notice Verify signature validity using ERC-1271 standard for contract-based authentication.
	 * @param hash      Hash of the data that was signed.
	 * @param signature Signature bytes to verify.
	 * @return Magic value (0x1626ba7e) if signature is valid, 0xffffffff otherwise.
	 *
	 * @dev Delegates signature verification to the MultiAccount contract which
	 *      manages account ownership and signature validation logic.
	 */
	function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
		return IMultiAccount(multiAccountAddress).verifySignatureOfAccount(address(this), hash, signature);
	}

	/* ─────────────────────────────── Modifiers ─────────────────────────────── */

	/**
	 * @notice Restricts function access to only the designated MultiAccount contract.
	 * @param sender Address attempting to call the function.
	 */
	modifier onlyMultiAccount(address sender) {
		if (multiAccountAddress != sender) revert OnlyMultiAccount(sender, multiAccountAddress);
		_;
	}
}
