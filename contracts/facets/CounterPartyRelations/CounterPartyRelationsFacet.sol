// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibCounterPartyRelations } from "../../libraries/core/LibCounterPartyRelations.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";

import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { ICounterPartyRelationsFacet } from "./ICounterPartyRelationsFacet.sol";

/**
 * @title CounterPartyRelationsFacet
 * @notice Manages PartyA/PartyB relationships
 * @dev Implements the ICounterPartyRelationsFacet interface with access control and pausability
 */
contract CounterPartyRelationsFacet is Accessibility, Pausable, ICounterPartyRelationsFacet {
	using LibParty for address;

	/**
	 * @notice Enables the instant action mode for a PartyA
	 * @dev Only callable by PartyA accounts, not PartyB
	 */
	function activateInstantActionMode() external onlyNotPartyB(msg.sender) whenInstantModeIsNotActive(msg.sender) whenPartyNotPaused(msg.sender) {
		LibCounterPartyRelations.activateInstantActionMode();
		emit ActivateInstantActionMode(msg.sender, block.timestamp);
	}

	/**
	 * @notice Initiates the process to deactivate instant action mode
	 * @dev Only callable by PartyA accounts, starts a time-delayed process
	 */
	function proposeToDeactivateInstantActionMode()
		external
		onlyNotPartyB(msg.sender)
		whenInstantModeIsActive(msg.sender)
		whenPartyNotPaused(msg.sender)
	{
		LibCounterPartyRelations.proposeToDeactivateInstantActionMode();
		emit ProposeToDeactivateInstantActionMode(msg.sender, block.timestamp);
	}

	/**
	 * @notice Completes the deactivation of instant action mode after proposal
	 * @dev Only callable by PartyA accounts after the waiting period has passed
	 */
	function deactivateInstantActionMode() external onlyNotPartyB(msg.sender) whenPartyNotPaused(msg.sender) {
		LibCounterPartyRelations.deactivateInstantActionMode();
		emit DeactivateInstantActionMode(msg.sender, block.timestamp);
	}

	/**
	 * @notice Creates a binding relationship between a PartyA and a PartyB
	 * @dev Only callable by PartyA accounts when PartyA actions are not paused
	 * @param partyB The address of the PartyB to establish a relationship with
	 */
	function bindToPartyB(address partyB) external onlyNotPartyB(msg.sender) whenPartyNotPaused(msg.sender) {
		LibCounterPartyRelations.bindToPartyB(partyB);
		emit BindToPartyB(msg.sender, partyB);
	}

	/**
	 * @notice Begins the process of terminating a relationship with a PartyB
	 * @dev Starts a cooldown period before the unbinding can be completed
	 */
	function initiateUnbindingFromPartyB() external onlyNotPartyB(msg.sender) whenPartyNotPaused(msg.sender) {
		LibCounterPartyRelations.initiateUnbindingFromPartyB();
		emit InitiateUnbindingFromPartyB(msg.sender, CounterPartyRelationsStorage.layout().boundPartyB[msg.sender], block.timestamp);
	}

	/**
	 * @notice Finalizes the unbinding process from a PartyB after the cooldown period
	 * @dev Only callable after the required waiting period from initiation has passed
	 */
	function completeUnbindingFromPartyB() external onlyNotPartyB(msg.sender) whenPartyNotPaused(msg.sender) {
		address previousPartyB = CounterPartyRelationsStorage.layout().boundPartyB[msg.sender];
		LibCounterPartyRelations.completeUnbindingFromPartyB();
		emit CompleteUnbindingFromPartyB(msg.sender, previousPartyB);
	}

	/**
	 * @notice Revokes a pending request to unbind from a PartyB
	 * @dev Can only be called during the cooldown period after initiation
	 */
	function cancelUnbindingFromPartyB() external onlyNotPartyB(msg.sender) whenPartyNotPaused(msg.sender) {
		LibCounterPartyRelations.cancelUnbindingFromPartyB();
		emit CancelUnbindingFromPartyB(msg.sender, CounterPartyRelationsStorage.layout().boundPartyB[msg.sender]);
	}
}
