// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../facets/Trade/ITradeFacet.sol";
import "../facets/View/IViewFacet.sol";
import "../facets/Account/IAccountFacet.sol";
import "../facets/Control/IControlFacet.sol";
import "../facets/DiamondCut/IDiamondCut.sol";
import "../facets/DiamondLoupe/IDiamondLoupe.sol";
import "../facets/PartyAOpen/IPartyAOpenFacet.sol";
import "../facets/PartyBOpen/IPartyBOpenFacet.sol";
import "../facets/PartyAClose/IPartyACloseFacet.sol";
import "../facets/PartyBClose/IPartyBCloseFacet.sol";
import "../facets/ForceActions/IForceActionsFacet.sol";
import "../facets/ClearingHouse/IClearingHouseFacet.sol";

interface ISymmio is
	IAccountFacet,
	ITradeFacet,
	IClearingHouseFacet,
	IControlFacet,
	IForceActionsFacet,
	IPartyAOpenFacet,
	IPartyACloseFacet,
	IPartyBOpenFacet,
	IPartyBCloseFacet,
	IViewFacet,
	IDiamondCut,
	IDiamondLoupe
{}
