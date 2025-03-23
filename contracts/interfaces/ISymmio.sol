// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../facets/Account/IAccountFacet.sol";
import "../facets/Bridge/IBridgeFacet.sol";
import "../facets/ClearingHouse/IClearingHouseFacet.sol";
import "../facets/Control/IControlFacet.sol";
import "../facets/ForceActions/IForceActionsFacet.sol";
import "../facets/InstantActionsOpen/IInstantActionsOpenFacet.sol";
import "../facets/InstantActionsClose/IInstantActionsCloseFacet.sol";
import "../facets/Interdealer/IInterdealerFacet.sol";
import "../facets/DiamondCut/IDiamondCut.sol";
import "../facets/DiamondLoup/IDiamondLoupe.sol";
import "../facets/PartyAOpen/IPartyAOpenFacet.sol";
import "../facets/PartyAClose/IPartyACloseFacet.sol";
import "../facets/PartyBOpen/IPartyBOpenFacet.sol";
import "../facets/PartyBClose/IPartyBCloseFacet.sol";
import "../facets/ViewFacet/IViewFacet.sol";

interface ISymmio is
IAccountFacet,
IBridgeFacet,
IClearingHouseFacet,
IControlFacet,
IForceActionsFacet,
IInstantActionsOpenFacet,
IInstantActionsCloseFacet,
IInterdealerFacet,
IPartyAOpenFacet,
IPartyACloseFacet,
IPartyBOpenFacet,
IPartyBCloseFacet,
IViewFacet,
IDiamondCut,
IDiamondLoupe
{

}
