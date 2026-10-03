// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;
import { LibBucket } from "./LibBucket.sol";
import { BucketStorage } from "../../storages/BucketStorage.sol";
import { BucketErrors } from "../../errors/BucketErrors.sol";

import { LibParty } from "../models/LibParty.sol";

import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { PartyRelationsErrors } from "../../errors/PartyRelationsErrors.sol";

library LibCounterPartyRelations {
	using LibParty for address;

	function activateInstantActionMode() internal {
		if (LibBucket.boundPartyBBucketId(msg.sender, 0) != 0) revert BucketErrors.NativeIntegrationUnsupported();
		if (CounterPartyRelationsStorage.layout().boundPartyB[msg.sender] == address(0))
			revert PartyRelationsErrors.BoundedPartyBNotFound(msg.sender);
		CounterPartyRelationsStorage.layout().instantActionsMode[msg.sender] = true;
	}

	function proposeToDeactivateInstantActionMode() internal {
		CounterPartyRelationsStorage.Layout storage layout = CounterPartyRelationsStorage.layout();
		layout.instantActionsModeDeactivateTime[msg.sender] = block.timestamp + layout.deactiveInstantActionModeCooldown;
	}

	function deactivateInstantActionMode() internal {
		CounterPartyRelationsStorage.Layout storage layout = CounterPartyRelationsStorage.layout();

		if (layout.instantActionsModeDeactivateTime[msg.sender] == 0) revert PartyRelationsErrors.DeactivationNotProposed(msg.sender);

		if (layout.instantActionsModeDeactivateTime[msg.sender] > block.timestamp) {
			revert ValidationErrors.CooldownNotOver(
				"instantActionsModeDeactivateTime",
				block.timestamp,
				layout.instantActionsModeDeactivateTime[msg.sender]
			);
		}

		layout.instantActionsMode[msg.sender] = false;
		layout.instantActionsModeDeactivateTime[msg.sender] = 0;
	}

	function bindToPartyB(address partyB) internal {
		bindToPartyB(0, partyB, 0);
	}
	function bindToPartyB(uint256 bucketId, address partyB, uint256 partyBBucketId) internal {
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		LibBucket.requireRegistered(msg.sender, bucketId);
		LibBucket.requireRegistered(partyB, partyBBucketId);
		if (!partyB.isPartyB()) revert PartyRelationsErrors.PartyBNotActive(partyB);
		address current = LibBucket.boundPartyB(msg.sender, bucketId);
		if (current != address(0)) revert PartyRelationsErrors.BoundedToAnotherPartyB(msg.sender, current);
		if (bucketId == 0) CounterPartyRelationsStorage.layout().boundPartyB[msg.sender] = partyB;
		else BucketStorage.layout().boundPartyBs[msg.sender][bucketId] = partyB;
		BucketStorage.layout().boundPartyBBucketIds[msg.sender][bucketId] = partyBBucketId;
	}
	function initiateUnbindingFromPartyB() internal {
		initiateUnbindingFromPartyB(0);
	}
	function initiateUnbindingFromPartyB(uint256 bucketId) internal {
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		if (LibBucket.boundPartyB(msg.sender, bucketId) == address(0)) revert PartyRelationsErrors.BoundedPartyBNotFound(msg.sender);
		if (bucketId == 0 && CounterPartyRelationsStorage.layout().instantActionsMode[msg.sender])
			revert PartyRelationsErrors.InstantModeActive(msg.sender);
		uint256 time = _unbindingTime(msg.sender, bucketId);
		if (time != 0) revert PartyRelationsErrors.UnbindingAlreadyInProgress(msg.sender, time);
		_setUnbindingTime(msg.sender, bucketId, block.timestamp);
	}
	function completeUnbindingFromPartyB() internal {
		completeUnbindingFromPartyB(0);
	}
	function completeUnbindingFromPartyB(uint256 bucketId) internal {
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		if (LibBucket.boundPartyB(msg.sender, bucketId) == address(0)) revert PartyRelationsErrors.BoundedPartyBNotFound(msg.sender);
		uint256 time = _unbindingTime(msg.sender, bucketId);
		if (time == 0) revert PartyRelationsErrors.UnbindingNotInitiated(msg.sender);
		uint256 required = time + CounterPartyRelationsStorage.layout().unbindingCooldown;
		if (block.timestamp < required) revert ValidationErrors.CooldownNotOver("unbinding", block.timestamp, required);
		if (bucketId == 0) delete CounterPartyRelationsStorage.layout().boundPartyB[msg.sender];
		else delete BucketStorage.layout().boundPartyBs[msg.sender][bucketId];
		delete BucketStorage.layout().boundPartyBBucketIds[msg.sender][bucketId];
		_setUnbindingTime(msg.sender, bucketId, 0);
	}
	function cancelUnbindingFromPartyB() internal {
		cancelUnbindingFromPartyB(0);
	}
	function cancelUnbindingFromPartyB(uint256 bucketId) internal {
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		if (_unbindingTime(msg.sender, bucketId) == 0) revert PartyRelationsErrors.UnbindingNotInitiated(msg.sender);
		_setUnbindingTime(msg.sender, bucketId, 0);
	}
	function _unbindingTime(address owner, uint256 bucketId) private view returns (uint256) {
		return
			bucketId == 0
				? CounterPartyRelationsStorage.layout().unbindingRequestTime[owner]
				: BucketStorage.layout().unbindingRequestTimes[owner][bucketId];
	}
	function _setUnbindingTime(address owner, uint256 bucketId, uint256 time) private {
		if (bucketId == 0) CounterPartyRelationsStorage.layout().unbindingRequestTime[owner] = time;
		else BucketStorage.layout().unbindingRequestTimes[owner][bucketId] = time;
	}
}
