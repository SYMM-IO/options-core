// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license

///////////////////////////////////////////////////////////////////////////
// @author droplet ////////////////////////////////////////////////////////
///////////////////////// Code Flow ///////////////////////////////////////
///////////////////////////////////////////////////////////////////////////
// 1: Flagging the appropriate Party //////////////////////////////////////
// 2: Allocating Reserve if Available/Needed //////////////////////////////
// --NOTE if Allocation Resolves the Solvency Moves to stage 7 ////////////
// 3: Liquidating the appropriate Party ///////////////////////////////////
// 4: Closing the Trades -> CloseIntents -> OpenIntents ///////////////////
// 5: ConfiscateWithdrawal the party
// 5: Confiscate the Party Balance as needed //////////////////////////////
// 6: Distributing the Collateral /////////////////////////////////////////
// 7: Unflag Party ////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////

pragma solidity >=0.8.19;
import { ClearingHouseLiquidationFacet } from "./ClearingHouseLiquidationFacet.sol";
import { ClearingHouseSettlementFacet } from "./ClearingHouseSettlementFacet.sol";

/// @notice Complete Diamond client ABI; deploy the concrete implementation facets.
abstract contract ClearingHouseFacet is ClearingHouseLiquidationFacet, ClearingHouseSettlementFacet {}
