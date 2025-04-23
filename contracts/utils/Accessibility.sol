// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibAccessibility } from "../libraries/LibAccessibility.sol";

import { AppStorage } from "../storages/AppStorage.sol";
import { TradeStorage } from "../storages/TradeStorage.sol";
import { AccountStorage } from "../storages/AccountStorage.sol";
import { StateControlStorage } from "../storages/StateControlStorage.sol";
import { CounterPartyRelationsStorage } from "../storages/CounterPartyRelationsStorage.sol";

import { Trade } from "../types/TradeTypes.sol";
import { Withdraw } from "../types/WithdrawTypes.sol";

abstract contract Accessibility {
	// Custom errors
	error NotPartyB(address sender);
	error IsPartyB(address sender);
	error UserIsPartyB(address user);
	error MissingRole(address sender, bytes32 role);
	error NotPartyAOfTrade(address sender, uint256 tradeId, address partyA);
	error NotPartyBOfTrade(address sender, uint256 tradeId, address partyB);
	error UserSuspended(address user);
	error ReceiverSuspended(address receiver);
	error SuspendedWithdrawal(uint256 withdrawId);
	error InstantActionModeActive(address sender);

	modifier onlyPartyB() {
		if (!AppStorage.layout().partyBConfigs[msg.sender].isActive) revert NotPartyB(msg.sender);
		_;
	}

	modifier notPartyB() {
		if (AppStorage.layout().partyBConfigs[msg.sender].isActive) revert IsPartyB(msg.sender);
		_;
	}

	modifier userNotPartyB(address user) {
		if (AppStorage.layout().partyBConfigs[user].isActive) revert UserIsPartyB(user);
		_;
	}

	modifier onlyRole(bytes32 role) {
		if (!LibAccessibility.hasRole(msg.sender, role)) revert MissingRole(msg.sender, role);
		_;
	}

	modifier onlyPartyAOfTrade(uint256 tradeId) {
		Trade storage trade = TradeStorage.layout().trades[tradeId];
		if (trade.partyA != msg.sender) revert NotPartyAOfTrade(msg.sender, tradeId, trade.partyA);
		_;
	}

	modifier onlyPartyBOfTrade(uint256 tradeId) {
		Trade storage trade = TradeStorage.layout().trades[tradeId];
		if (trade.partyB != msg.sender) revert NotPartyBOfTrade(msg.sender, tradeId, trade.partyB);
		_;
	}

	modifier notSuspended(address user) {
		if (StateControlStorage.layout().suspendedAddresses[user]) revert UserSuspended(user);
		_;
	}

	modifier notSuspendedWithdrawal(uint256 withdrawId) {
		Withdraw storage withdrawObject = AccountStorage.layout().withdrawals[withdrawId];
		StateControlStorage.Layout storage stateControlLayout = StateControlStorage.layout();
		if (stateControlLayout.suspendedAddresses[withdrawObject.user]) revert UserSuspended(withdrawObject.user);
		if (stateControlLayout.suspendedAddresses[withdrawObject.to]) revert ReceiverSuspended(withdrawObject.to);
		if (stateControlLayout.suspendedWithdrawal[withdrawId]) revert SuspendedWithdrawal(withdrawId);
		_;
	}

	modifier inactiveInstantMode(address sender) {
		if (CounterPartyRelationsStorage.layout().instantActionsMode[sender]) revert InstantActionModeActive(sender);
		_;
	}
}
