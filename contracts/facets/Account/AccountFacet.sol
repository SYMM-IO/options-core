// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;
import { AccountBalanceFacet } from "./AccountBalanceFacet.sol";
import { AccountAllocationFacet } from "./AccountAllocationFacet.sol";
import { AccountWithdrawFacet } from "./AccountWithdrawFacet.sol";
/// @notice Complete account ABI for attaching to the Diamond; deploy its responsibility facets separately.
abstract contract AccountFacet is AccountBalanceFacet, AccountAllocationFacet, AccountWithdrawFacet {}
