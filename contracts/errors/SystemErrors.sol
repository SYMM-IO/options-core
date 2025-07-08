// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library SystemErrors {
	// Diamond operations
	error NotContractOwner(address sender, address owner);
	error NotPendingOwner(address sender, address pendingOwner);
	error IncorrectFacetCutAction(uint8 action);
	error NoSelectorsInFacet();
	error CannotAddExistingFunction(bytes4 selector);
	error NoRemoveTarget(bytes4 selector);
	error CannotRemoveImmutableFunction(bytes4 selector);
	error IdenticalReplace(bytes4 selector, address facetAddress);
	error NoReplaceTarget(bytes4 selector);
	error ImmutableReplace(bytes4 selector);
	error ZeroAddressWithNonemptyCalldata();
	error NonZeroAddressWithEmptyCalldata();
	error InitFunctionReverted();
	error ContractHasNoCode(address contractAddress, string errorMessage);
	error InvalidRemoveFacetAddress(address providedAddress);
	error InvalidAddFacetAddress();
	error InvalidReplaceFacetAddress();
	error FunctionDoesNotExist(bytes4 functionSelector);

	// Pausable states
	error GlobalPaused();
	error ExpressWithdrawPaused();
	error ExpressWithdrawCollectionPaused();
	error DepositingPaused();
	error InternalTransferPaused();
	error ExternalTransferPaused();
	error WithdrawingPaused();
	error PartyAActionsPaused();
	error PartyBActionsPaused();
	error ThirdPartyActionsPaused();
	error LiquidatingPaused();
	error InstantLayerPaused();

	// Emergency states
	error PartyBInEmergencyMode(address partyB);
	error PartyBsInEmergencyMode();

	// Suspension/Status validation
	error UserSuspended(address user);
	error WithdrawalSuspended(uint256 withdrawId);
}
