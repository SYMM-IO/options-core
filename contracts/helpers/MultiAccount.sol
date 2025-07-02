// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { ISymmio } from "../interfaces/ISymmio.sol";
import { IMultiAccount } from "../interfaces/IMultiAccount.sol";
import { ISymmioPartyA } from "../interfaces/ISymmioPartyA.sol";

import { SignatureVerifier } from "./SignatureVerifier.sol";

contract MultiAccount is IMultiAccount, Initializable, SignatureVerifier, PausableUpgradeable, AccessControlUpgradeable {
	using SafeERC20Upgradeable for IERC20Upgradeable;

	// ==================== CUSTOM ERRORS ====================
	error NotOwnerOfAccount(address sender, address account, address owner);
	error ContractDeploymentFailed();
	error PartyACallFailed(bytes returnData);
	error InvalidCallData(bytes callData);
	error UnauthorizedAccess(address account, address sender, bytes4 selector);

	// ==================== CONSTANTS ====================
	bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

	// ==================== STATE VARIABLES ====================
	address public symmioAddress; // Address of the Symmio platform
	uint256 public saltCounter; // Counter for generating unique addresses with create2
	bytes public accountImplementation;

	// Account mappings
	mapping(address => Account[]) public accounts; // User to their accounts mapping
	mapping(address => uint256) public indexOfAccount; // Account to its index mapping
	mapping(address => address) public owners; // Account to its owner mapping

	// ===================== MODIFIERS =====================
	/**
	 * @dev Modifier to check if the sender is the owner of the account
	 * @param account The account address to check ownership for
	 * @param sender The address to verify as owner
	 */
	modifier onlyOwner(address account, address sender) {
		if (owners[account] != sender) revert NotOwnerOfAccount(sender, account, owners[account]);
		_;
	}

	// ==================== CONSTRUCTOR & INITIALIZER ====================

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/**
	 * @dev Initializes the contract with necessary parameters.
	 * @param admin The admin address for the accounts contracts.
	 * @param symmioAddress_ The address of the Symmio platform.
	 * @param accountImplementation_ The bytecode of the account implementation contract.
	 */
	function initialize(address admin, address symmioAddress_, bytes memory accountImplementation_) public initializer {
		__Pausable_init();
		__AccessControl_init();

		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		_grantRole(PAUSER_ROLE, admin);
		_grantRole(UNPAUSER_ROLE, admin);
		_grantRole(SETTER_ROLE, admin);
		symmioAddress = symmioAddress_;
		accountImplementation = accountImplementation_;
	}

	// ==================== SETTER FUNCTIONS ====================
	/**
	 * @dev Sets the implementation contract for the account.
	 * @param accountImplementation_ The bytecodes of the new implementation contract.
	 */
	function setAccountImplementation(bytes memory accountImplementation_) external onlyRole(SETTER_ROLE) {
		emit SetAccountImplementation(accountImplementation, accountImplementation_);
		accountImplementation = accountImplementation_;
	}

	/**
	 * @dev Sets the address of the Symmio platform.
	 * @param addr The address of the Symmio platform.
	 */
	function setSymmioAddress(address addr) external onlyRole(SETTER_ROLE) {
		emit SetSymmioAddress(symmioAddress, addr);
		symmioAddress = addr;
	}

	// ================ CONTRACT DEPLOYMENT FUNCTIONS ================
	/**
	 * @dev Internal function to deploy a new party A account contract.
	 * @return account The address of the newly deployed account contract.
	 */
	function _deployPartyA() internal returns (address account) {
		bytes32 salt = keccak256(abi.encodePacked("MultiAccount_", saltCounter));
		saltCounter += 1;

		bytes memory bytecode = abi.encodePacked(accountImplementation, abi.encode(address(this), symmioAddress));
		account = _deployContract(bytecode, salt);
		return account;
	}

	/**
	 * @dev Internal function to deploy a contract with create2.
	 * @param bytecode The bytecode of the contract to be deployed.
	 * @param salt The salt used for contract deployment.
	 * @return contractAddress The address of the deployed contract.
	 */
	function _deployContract(bytes memory bytecode, bytes32 salt) internal returns (address contractAddress) {
		assembly {
			contractAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
		}
		if (contractAddress == address(0)) revert ContractDeploymentFailed();
		emit DeployContract(msg.sender, contractAddress);
		return contractAddress;
	}

	// =================== PAUSE FUNCTIONS ===================
	/**
	 * @dev Pauses the contract, preventing execution of transactions.
	 */
	function pause() external onlyRole(PAUSER_ROLE) {
		_pause();
	}

	/**
	 * @dev Unpauses the contract, allowing execution of transactions.
	 */
	function unpause() external onlyRole(UNPAUSER_ROLE) {
		_unpause();
	}

	// ================ ACCOUNT MANAGEMENT FUNCTIONS ================
	/**
	 * @dev Adds a new account for the caller with the specified name.
	 * @param name The name of the new account.
	 */
	function addAccount(string memory name) external whenNotPaused {
		address account = _deployPartyA();
		indexOfAccount[account] = accounts[msg.sender].length;
		accounts[msg.sender].push(Account(account, name));
		owners[account] = msg.sender;
		emit AddAccount(msg.sender, account, name);
	}

	/**
	 * @dev Edits the name of the specified account.
	 * @param accountAddress The address of the account to edit.
	 * @param name The new name for the account.
	 */
	function editAccountName(address accountAddress, string memory name) external whenNotPaused {
		uint256 index = indexOfAccount[accountAddress];
		accounts[msg.sender][index].name = name;
		emit EditAccountName(msg.sender, accountAddress, name);
	}

	/**
	 * @dev Allows the admin to execute an arbitrary admin call on a PartyA contract.
	 * @param partyA The address of the PartyA contract.
	 * @param data The calldata for the admin call.
	 *
	 * This function can be used to forward any admin-level operation to the PartyA contract.
	 * Requirements:
	 * - Caller must have the SETTER_ROLE.
	 * - The call must succeed, otherwise the transaction reverts.
	 */
	function adminCallPartyA(address partyA, bytes calldata data) external onlyRole(SETTER_ROLE) {
		(bool success, bytes memory returnData) = partyA.call(data);
		if (!success) revert PartyACallFailed(returnData);
		emit AdminPartyACall(partyA, data, success, returnData);
	}

	// ================ CALL MANAGEMENT FUNCTIONS ================
	/**
	 * @dev Send a call to symmio from partyA account.
	 * @param account The address of the account to execute the calls on behalf of.
	 * @param _callData The input calldata to pass by the call.
	 */
	function innerCall(address account, bytes memory _callData) internal {
		(bool _success, bytes memory _resultData) = ISymmioPartyA(account).call(_callData);
		emit Call(msg.sender, account, _callData, _success, _resultData);
		if (!_success) {
			assembly {
				revert(add(_resultData, 32), mload(_resultData))
			}
		}
	}

	/**
	 * @dev Executes a series of calls on behalf of the specified account.
	 * @param account The address of the account to execute the calls on behalf of.
	 * @param _callDatas An array of call data to execute.
	 */
	function _call(address account, bytes[] memory _callDatas) external whenNotPaused {
		if (msg.sender != owners[account] && !ISymmio(symmioAddress).isCallFromInstantLayer())
			revert UnauthorizedAccess(account, msg.sender, bytes4(0));
		for (uint8 i; i < _callDatas.length; i++) innerCall(account, _callDatas[i]);
	}

	/**
	 * @dev Verifies the signature of an account owner.
	 * @param account The address of the account.
	 * @param hash The hash of the data signed.
	 * @param signature The signature generated by the signer.
	 * @return magic value if the signature is valid.
	 */
	function verifySignatureOfAccount(address account, bytes32 hash, bytes calldata signature) external view returns (bytes4) {
		return isValidSignatureEIP1271(owners[account], hash, signature);
	}

	// ==================== VIEW FUNCTIONS ====================
	/**
	 * @dev Returns the number of accounts belonging to the specified user.
	 * @param user The address of the user.
	 * @return The number of accounts.
	 */
	function getAccountsLength(address user) external view returns (uint256) {
		return accounts[user].length;
	}

	/**
	 * @dev Returns an array of accounts belonging to the specified user.
	 * @param user The address of the user.
	 * @param start The index to start retrieving accounts from.
	 * @param size The maximum number of accounts to retrieve.
	 * @return An array of Account structures.
	 */
	function getAccounts(address user, uint256 start, uint256 size) external view returns (Account[] memory) {
		uint256 len = size > accounts[user].length - start ? accounts[user].length - start : size;
		Account[] memory userAccounts = new Account[](len);
		for (uint256 i = start; i < start + len; i++) {
			userAccounts[i - start] = accounts[user][i];
		}
		return userAccounts;
	}
}
