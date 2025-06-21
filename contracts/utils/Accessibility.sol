// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibAccessibility } from "../libraries/core/LibAccessibility.sol";
import { LibParty } from "../libraries/models/LibParty.sol";

import { TradeStorage } from "../storages/TradeStorage.sol";
import { AccountStorage } from "../storages/AccountStorage.sol";
import { StateControlStorage } from "../storages/StateControlStorage.sol";
import { CounterPartyRelationsStorage } from "../storages/CounterPartyRelationsStorage.sol";

import { Trade } from "../types/TradeTypes.sol";
import { Withdraw } from "../types/WithdrawTypes.sol";

import { AccessibilityErrors } from "../errors/AccessibilityErrors.sol";

abstract contract Accessibility {
	using LibParty for address;

	modifier onlyPartyB(address user) {
		if (!user.isPartyB()) revert AccessibilityErrors.NotPartyB(user);
		_;
	}

	modifier onlyNotPartyB(address user) {
		if (user.isPartyB()) revert AccessibilityErrors.UserIsPartyB(user);
		_;
	}

	modifier onlyRole(bytes32 role) {
		if (!LibAccessibility.hasRole(msg.sender, role)) revert AccessibilityErrors.MissingRole(msg.sender, role);
		_;
	}

	modifier onlyPartyAOfTrade(uint256 tradeId) {
		Trade storage trade = TradeStorage.layout().trades[tradeId];
		if (trade.partyA != msg.sender) revert AccessibilityErrors.NotPartyAOfTrade(msg.sender, tradeId, trade.partyA);
		_;
	}

	modifier onlyPartyBOfTrade(uint256 tradeId) {
		Trade storage trade = TradeStorage.layout().trades[tradeId];
		if (trade.partyB != msg.sender) revert AccessibilityErrors.NotPartyBOfTrade(msg.sender, tradeId, trade.partyB);
		_;
	}

	modifier whenNotSuspended(address user) {
		if (StateControlStorage.layout().suspendedAddresses[user]) revert AccessibilityErrors.UserSuspended(user);
		_;
	}

	modifier whenWithdrawalNotSuspended(uint256 withdrawId) {
		checkNotSuspendedWithdrawal(withdrawId); // To reduce code size
		_;
	}

	function checkNotSuspendedWithdrawal(uint256 withdrawId) internal view {
		Withdraw storage withdrawObject = AccountStorage.layout().withdrawals[withdrawId];
		StateControlStorage.Layout storage stateControlLayout = StateControlStorage.layout();
		if (stateControlLayout.suspendedAddresses[withdrawObject.user]) revert AccessibilityErrors.UserSuspended(withdrawObject.user);
		if (stateControlLayout.suspendedAddresses[withdrawObject.to]) revert AccessibilityErrors.ReceiverSuspended(withdrawObject.to);
		if (stateControlLayout.suspendedWithdrawal[withdrawId]) revert AccessibilityErrors.SuspendedWithdrawal(withdrawId);
	}

	modifier whenInstantModeIsNotActive(address sender) {
		if (CounterPartyRelationsStorage.layout().instantActionsMode[sender]) revert AccessibilityErrors.InstantModeActive(sender);
		_;
	}

	modifier whenInstantModeIsActive(address sender) {
		if (!CounterPartyRelationsStorage.layout().instantActionsMode[sender]) revert AccessibilityErrors.InstantActionModeNotActive(sender);
		_;
	}
}
