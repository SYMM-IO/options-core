// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
/******************************************************************************/

import { IDiamondCut } from "../../facets/DiamondCut/IDiamondCut.sol";
import { DiamondErrors } from "../../errors/DiamondErrors.sol";

library LibDiamond {
	bytes32 public constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

	struct FacetAddressAndSelectorPosition {
		address facetAddress;
		uint16 selectorPosition;
	}

	struct DiamondStorage {
		// function selector => facet address and selector position in selectors array
		mapping(bytes4 => FacetAddressAndSelectorPosition) facetAddressAndSelectorPosition;
		bytes4[] selectors;
		mapping(bytes4 => bool) supportedInterfaces;
		// owner of the contract
		address contractOwner;
		// address of new Owner
		address pendingOwner;
	}

	function diamondStorage() internal pure returns (DiamondStorage storage ds) {
		bytes32 position = DIAMOND_STORAGE_POSITION;
		assembly {
			ds.slot := position
		}
	}

	event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
	event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);

	function setContractOwner(address _newOwner) internal {
		DiamondStorage storage ds = diamondStorage();
		address previousOwner = ds.contractOwner;
		ds.contractOwner = _newOwner;
		emit OwnershipTransferred(previousOwner, _newOwner);
	}

	function transferOwnership(address _newOwner) internal {
		DiamondStorage storage ds = diamondStorage();
		ds.pendingOwner = _newOwner;
		emit OwnershipTransferStarted(ds.contractOwner, _newOwner);
	}

	function acceptOwnership() internal {
		DiamondStorage storage ds = diamondStorage();
		if (msg.sender != ds.pendingOwner) revert DiamondErrors.NotPendingOwner(msg.sender, ds.pendingOwner);
		address previousOwner = ds.contractOwner;
		ds.contractOwner = ds.pendingOwner;
		ds.pendingOwner = address(0);
		emit OwnershipTransferred(previousOwner, ds.contractOwner);
	}

	function contractOwner() internal view returns (address contractOwner_) {
		contractOwner_ = diamondStorage().contractOwner;
	}

	function enforceIsOwnerOrContract() internal view {
		if (msg.sender != diamondStorage().contractOwner && msg.sender != address(this))
			revert DiamondErrors.NotOwnerOrContract(msg.sender, diamondStorage().contractOwner, address(this));
	}

	function enforceIsContractOwner() internal view {
		if (msg.sender != diamondStorage().contractOwner) revert DiamondErrors.NotContractOwner(msg.sender, diamondStorage().contractOwner);
	}

	event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

	// Internal function version of diamondCut
	function diamondCut(IDiamondCut.FacetCut[] memory _diamondCut, address _init, bytes memory _calldata) internal {
		for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
			IDiamondCut.FacetCutAction action = _diamondCut[facetIndex].action;
			if (action == IDiamondCut.FacetCutAction.Add) {
				addFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
			} else if (action == IDiamondCut.FacetCutAction.Replace) {
				replaceFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
			} else if (action == IDiamondCut.FacetCutAction.Remove) {
				removeFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
			} else {
				revert DiamondErrors.IncorrectFacetCutAction(uint8(action));
			}
		}
		emit DiamondCut(_diamondCut, _init, _calldata);
		initializeDiamondCut(_init, _calldata);
	}

	function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
		if (_functionSelectors.length == 0) revert DiamondErrors.NoSelectorsInFacet();

		DiamondStorage storage ds = diamondStorage();
		uint16 selectorCount = uint16(ds.selectors.length);

		if (_facetAddress == address(0)) revert DiamondErrors.InvalidAddFacetAddress();

		enforceHasContractCode(_facetAddress, "LibDiamondCut: Add facet has no code");

		for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
			bytes4 selector = _functionSelectors[selectorIndex];
			address oldFacetAddress = ds.facetAddressAndSelectorPosition[selector].facetAddress;
			if (oldFacetAddress != address(0)) revert DiamondErrors.CannotAddExistingFunction(selector);

			ds.facetAddressAndSelectorPosition[selector] = FacetAddressAndSelectorPosition(_facetAddress, selectorCount);
			ds.selectors.push(selector);
			selectorCount++;
		}
	}

	function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
		if (_functionSelectors.length == 0) revert DiamondErrors.NoSelectorsInFacet();

		DiamondStorage storage ds = diamondStorage();

		if (_facetAddress == address(0)) revert DiamondErrors.InvalidReplaceFacetAddress();

		enforceHasContractCode(_facetAddress, "LibDiamondCut: Replace facet has no code");

		for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
			bytes4 selector = _functionSelectors[selectorIndex];
			address oldFacetAddress = ds.facetAddressAndSelectorPosition[selector].facetAddress;

			// can't replace immutable functions -- functions defined directly in the diamond
			if (oldFacetAddress == address(this)) revert DiamondErrors.ImmutableReplace(selector);

			if (oldFacetAddress == _facetAddress) revert DiamondErrors.IdenticalReplace(selector, _facetAddress);

			if (oldFacetAddress == address(0)) revert DiamondErrors.NoReplaceTarget(selector);

			// replace old facet address
			ds.facetAddressAndSelectorPosition[selector].facetAddress = _facetAddress;
		}
	}

	function removeFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
		if (_functionSelectors.length == 0) revert DiamondErrors.NoSelectorsInFacet();

		DiamondStorage storage ds = diamondStorage();
		uint256 selectorCount = ds.selectors.length;

		if (_facetAddress != address(0)) revert DiamondErrors.InvalidRemoveFacetAddress(_facetAddress);

		for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
			bytes4 selector = _functionSelectors[selectorIndex];
			FacetAddressAndSelectorPosition memory oldFacetAddressAndSelectorPosition = ds.facetAddressAndSelectorPosition[selector];

			if (oldFacetAddressAndSelectorPosition.facetAddress == address(0)) revert DiamondErrors.NoRemoveTarget(selector);

			// can't remove immutable functions -- functions defined directly in the diamond
			if (oldFacetAddressAndSelectorPosition.facetAddress == address(this)) revert DiamondErrors.CannotRemoveImmutableFunction(selector);

			// replace selector with last selector
			selectorCount--;
			if (oldFacetAddressAndSelectorPosition.selectorPosition != selectorCount) {
				bytes4 lastSelector = ds.selectors[selectorCount];
				ds.selectors[oldFacetAddressAndSelectorPosition.selectorPosition] = lastSelector;
				ds.facetAddressAndSelectorPosition[lastSelector].selectorPosition = oldFacetAddressAndSelectorPosition.selectorPosition;
			}
			// delete last selector
			ds.selectors.pop();
			delete ds.facetAddressAndSelectorPosition[selector];
		}
	}

	function initializeDiamondCut(address _init, bytes memory _calldata) internal {
		if (_init == address(0)) {
			if (_calldata.length != 0) revert DiamondErrors.ZeroAddressWithNonemptyCalldata();
		} else {
			if (_calldata.length == 0) revert DiamondErrors.NonZeroAddressWithEmptyCalldata();

			if (_init != address(this)) {
				enforceHasContractCode(_init, "LibDiamondCut: _init address has no code");
			}
			(bool success, bytes memory error) = _init.delegatecall(_calldata);
			if (!success) {
				if (error.length > 0) {
					// bubble up the error
					revert(string(error));
				} else {
					revert DiamondErrors.InitFunctionReverted();
				}
			}
		}
	}

	function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {
		uint256 contractSize;
		assembly {
			contractSize := extcodesize(_contract)
		}
		if (contractSize == 0) revert DiamondErrors.ContractHasNoCode(_contract, _errorMessage);
	}
}
