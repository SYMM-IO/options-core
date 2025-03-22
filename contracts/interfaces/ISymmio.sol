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
import "../facets/InstantActions/IInstantActionsFacet.sol";
import "../facets/Interdealer/IInterdealerFacet.sol";
import "../facets/DiamondCut/IDiamondCut.sol";
import "../facets/DiamondLoup/IDiamondLoupe.sol";
import "../facets/PartyA/IPartyAFacet.sol";
import "../facets/PartyB/IPartyBFacet.sol";
import "../facets/ViewFacet/IViewFacet.sol";

interface ISymmio is
IAccountFacet,
IBridgeFacet,
IClearingHouseFacet,
IControlFacet,
IForceActionsFacet,
IInstantActionsFacet,
IInterdealerFacet,
IPartyAFacet,
IPartyBFacet,
IViewFacet,
IDiamondCut,
IDiamondLoupe
{

}
