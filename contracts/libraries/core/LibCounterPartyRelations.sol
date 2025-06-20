// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";

import { CommonErrors } from "../utils/CommonErrors.sol";

import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";

import { CounterPartyRelationsFacetErrors } from "../../facets/CounterPartyRelations/CounterPartyRelationsFacetErrors.sol";

library LibCounterPartyRelations {
	using LibParty for address;

	function activateInstantActionMode() internal {
		if (CounterPartyRelationsStorage.layout().boundPartyB[msg.sender] == address(0)) revert CounterPartyRelationsFacetErrors.NotBoundToAnyPartyB(msg.sender);
		CounterPartyRelationsStorage.layout().instantActionsMode[msg.sender] = true;
	}

	function proposeToDeactivateInstantActionMode() internal {
		CounterPartyRelationsStorage.Layout storage layout = CounterPartyRelationsStorage.layout();
		layout.instantActionsModeDeactivateTime[msg.sender] = block.timestamp + layout.deactiveInstantActionModeCooldown;
	}

	function deactivateInstantActionMode() internal {
		CounterPartyRelationsStorage.Layout storage layout = CounterPartyRelationsStorage.layout();

		if (layout.instantActionsModeDeactivateTime[msg.sender] == 0) {
			revert CounterPartyRelationsFacetErrors.InstantActionModeDeactivationNotProposed(msg.sender);
		}

		if (layout.instantActionsModeDeactivateTime[msg.sender] > block.timestamp) {
			revert CommonErrors.CooldownNotOver(
				"instantActionsModeDeactivateTime",
				block.timestamp,
				layout.instantActionsModeDeactivateTime[msg.sender]
			);
		}

		layout.instantActionsMode[msg.sender] = false;
		layout.instantActionsModeDeactivateTime[msg.sender] = 0;
	}

	function bindToPartyB(address partyB) internal {
		CounterPartyRelationsStorage.Layout storage counterPartyRelationsLayout = CounterPartyRelationsStorage.layout();

		if (!partyB.isPartyB()) {
			revert CounterPartyRelationsFacetErrors.PartyBNotActive(partyB);
		}

		if (counterPartyRelationsLayout.boundPartyB[msg.sender] != address(0)) {
			revert CounterPartyRelationsFacetErrors.AlreadyBoundToPartyB(msg.sender, counterPartyRelationsLayout.boundPartyB[msg.sender]);
		}

		counterPartyRelationsLayout.boundPartyB[msg.sender] = partyB;
	}

	function initiateUnbindingFromPartyB() internal {
		CounterPartyRelationsStorage.Layout storage counterPartyRelationsLayout = CounterPartyRelationsStorage.layout();
		address currentPartyB = counterPartyRelationsLayout.boundPartyB[msg.sender];

		if (currentPartyB == address(0)) {
			revert CounterPartyRelationsFacetErrors.NotBoundToAnyPartyB(msg.sender);
		}

		if (counterPartyRelationsLayout.instantActionsMode[msg.sender]) {
			revert CounterPartyRelationsFacetErrors.InstantActionModeActive(msg.sender);
		}

		if (counterPartyRelationsLayout.unbindingRequestTime[msg.sender] != 0) {
			revert CounterPartyRelationsFacetErrors.UnbindingAlreadyInitiated(msg.sender, counterPartyRelationsLayout.unbindingRequestTime[msg.sender]);
		}

		counterPartyRelationsLayout.unbindingRequestTime[msg.sender] = block.timestamp;
	}

	function completeUnbindingFromPartyB() internal {
		CounterPartyRelationsStorage.Layout storage counterPartyRelationsLayout = CounterPartyRelationsStorage.layout();
		address currentPartyB = counterPartyRelationsLayout.boundPartyB[msg.sender];

		if (currentPartyB == address(0)) {
			revert CounterPartyRelationsFacetErrors.NotBoundToAnyPartyB(msg.sender);
		}

		if (counterPartyRelationsLayout.unbindingRequestTime[msg.sender] == 0) {
			revert CounterPartyRelationsFacetErrors.UnbindingNotInitiated(msg.sender);
		}

		uint256 requiredTime = counterPartyRelationsLayout.unbindingRequestTime[msg.sender] + counterPartyRelationsLayout.unbindingCooldown;
		if (block.timestamp < requiredTime) {
			revert CommonErrors.CooldownNotOver("unbinding", block.timestamp, requiredTime);
		}

		delete counterPartyRelationsLayout.boundPartyB[msg.sender];
		delete counterPartyRelationsLayout.unbindingRequestTime[msg.sender];
	}

	function cancelUnbindingFromPartyB() internal {
		CounterPartyRelationsStorage.Layout storage counterPartyRelationsLayout = CounterPartyRelationsStorage.layout();

		if (counterPartyRelationsLayout.unbindingRequestTime[msg.sender] == 0) {
			revert CounterPartyRelationsFacetErrors.UnbindingNotInitiated(msg.sender);
		}

		delete counterPartyRelationsLayout.unbindingRequestTime[msg.sender];
	}
}
