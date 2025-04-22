// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { MuonConfig, SchnorrSign } from "../types/MuonTypes.sol";

interface IMuonOracle {
	event ConfigUpdated(MuonConfig newConfig);
	event CheckGatewaySignatureUpdated(bool newValue);

	function verifyTSSAndGW(bytes32 _data, bytes calldata _reqId, SchnorrSign calldata _signature, bytes calldata _gatewaySignature) external view;

	function setConfig(MuonConfig memory _config) external;
}
