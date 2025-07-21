// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AccessControlStorage } from "../../storages/AccessControlStorage.sol";

library LibAccessibility {
	bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
	bytes32 public constant SYMBOL_MANAGER_ROLE = keccak256("SYMBOL_MANAGER_ROLE");
	bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
	bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
	bytes32 public constant PARTY_B_MANAGER_ROLE = keccak256("PARTY_B_MANAGER_ROLE");
	bytes32 public constant AFFILIATE_MANAGER_ROLE = keccak256("AFFILIATE_MANAGER_ROLE");
	bytes32 public constant AFFILIATE_FEE_MANAGER_ROLE = keccak256("AFFILIATE_FEE_MANAGER_ROLE");
	bytes32 public constant EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE = keccak256("EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE");
	bytes32 public constant SUSPENDER_ROLE = keccak256("SUSPENDER_ROLE");
	bytes32 public constant CLEARING_HOUSE_ROLE = keccak256("CLEARING_HOUSE_ROLE");
	bytes32 public constant DISPUTER_ROLE = keccak256("DISPUTER_ROLE");
	bytes32 public constant VIRTUAL_DEPOSITOR_ROLE = keccak256("VIRTUAL_DEPOSITOR_ROLE");
	bytes32 public constant WINDOW_UPDATER_ROLE = keccak256("WINDOW_UPDATER_ROLE");
	bytes32 public constant INSTANT_LAYER_ROLE = keccak256("INSTANT_LAYER_ROLE");

	/**
	 * @notice Checks if a user has a specific role.
	 * @param user The address of the user.
	 * @param role The role to check.
	 * @return Whether the user has the specified role.
	 */
	function hasRole(address user, bytes32 role) internal view returns (bool) {
		return AccessControlStorage.layout().hasRole[user][role];
	}
}
