// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;
import { PartyBOpenLifecycleFacet } from "./PartyBOpenLifecycleFacet.sol";
import { PartyBOpenFillFacet } from "./PartyBOpenFillFacet.sol";

/// @notice Complete Diamond client ABI; deploy the concrete implementation facets.
abstract contract PartyBOpenFacet is PartyBOpenLifecycleFacet, PartyBOpenFillFacet {}
