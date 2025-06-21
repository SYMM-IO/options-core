// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library PausableErrors {
	error GlobalPaused();
	error BridgePaused();
	error BridgeWithdrawPaused();
	error DepositingPaused();
	error InternalTransferPaused();
	error WithdrawingPaused();
	error PartyAActionsPaused();
	error PartyBActionsPaused();
	error ThirdPartyActionsPaused();
	error LiquidatingPaused();
	error EmergencyMode();
}
