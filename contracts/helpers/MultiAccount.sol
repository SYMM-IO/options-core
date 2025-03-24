// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IMultiAccount } from "../interfaces/IMultiAccount.sol";
import { ISymmio } from "../interfaces/ISymmio.sol";
import { ISymmioPartyA } from "../interfaces/ISymmioPartyA.sol";
import { SignatureVerifier } from "./SignatureVerifier.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract MultiAccount is IMultiAccount, Initializable, SignatureVerifier, PausableUpgradeable, AccessControlUpgradeable {
	using SafeERC20Upgradeable for IERC20Upgradeable;

	// ==================== CONSTANTS ====================
	bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

	// ==================== STATE VARIABLES ====================
	address public symmioAddress; // Address of the Symmio platform
	uint256 public saltCounter; // Counter for generating unique addresses with create2
	bytes public accountImplementation;
	uint256 public delegatedAccessRevokeCooldown;

	// Account mappings
	mapping(address => Account[]) public accounts; // User to their accounts mapping
	mapping(address => uint256) public indexOfAccount; // Account to its index mapping
	mapping(address => address) public owners; // Account to its owner mapping

	// Delegate access management
	mapping(address => mapping(address => mapping(bytes4 => bool))) public delegatedAccesses; // account -> target -> selector -> state
	mapping(address => mapping(address => mapping(bytes4 => uint256))) public revokeProposalTimestamp; // account -> target -> selector -> timestamp

	// ===================== MODIFIERS =====================
	/**
	 * @dev Modifier to check if the sender is the owner of the account
	 * @param account The account address to check ownership for
	 * @param sender The address to verify as owner
	 */
	modifier onlyOwner(address account, address sender) {
		require(owners[account] == sender, "MultiAccount: Sender isn't owner of account");
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

	// ================ ACCESS DELEGATION FUNCTIONS ================
	/**
	 * @dev Allows the owner of an account to delegate access to a specific function selector of a target contract.
	 * @param account The address of the account.
	 * @param target The address of the target contract.
	 * @param selector The function selector.
	 */
	function delegateAccess(address account, address target, bytes4 selector) external onlyOwner(account, msg.sender) {
		require(target != msg.sender && target != account, "MultiAccount: Invalid target");
		emit DelegateAccess(account, target, selector, true);
		delegatedAccesses[account][target][selector] = true;
	}

	/**
	 * @dev Allows the owner of an account to delegate access to a single target contract and multiple function selectors.
	 * @param account The address of the account.
	 * @param target The address of the target contract.
	 * @param selector An array of function selectors.
	 */
	function delegateAccesses(address account, address target, bytes4[] memory selector) external onlyOwner(account, msg.sender) {
		require(target != msg.sender && target != account, "MultiAccount: Invalid target");
		for (uint256 i = selector.length; i != 0; i--) {
			delegatedAccesses[account][target][selector[i - 1]] = true;
		}
		emit DelegateAccesses(account, target, selector, true);
	}

	/**
	 * @dev Allows the owner of an account to propose revoke access from a single target contract and multiple function selectors.
	 * @param account The address of the account.
	 * @param target The address of the target contract.
	 * @param selector An array of function selectors.
	 */
	function proposeToRevokeAccesses(address account, address target, bytes4[] memory selector) external onlyOwner(account, msg.sender) {
		require(target != msg.sender && target != account, "MultiAccount: Invalid target");
		for (uint256 i = selector.length; i != 0; i--) {
			revokeProposalTimestamp[account][target][selector[i - 1]] = block.timestamp;
		}
		emit ProposeToRevokeAccesses(account, target, selector);
	}

	/**
	 * @dev Allows the owner of an account to revoke access from a single target contract and multiple function selectors.
	 * @param account The address of the account.
	 * @param target The address of the target contract.
	 * @param selector An array of function selectors.
	 */
	function revokeAccesses(address account, address target, bytes4[] memory selector) external onlyOwner(account, msg.sender) {
		require(target != msg.sender && target != account, "MultiAccount: Invalid target");
		for (uint256 i = selector.length; i != 0; i--) {
			require(revokeProposalTimestamp[account][target][selector[i - 1]] != 0, "MultiAccount: Revoke access not proposed");
			require(
				revokeProposalTimestamp[account][target][selector[i - 1]] + delegatedAccessRevokeCooldown <= block.timestamp,
				"MultiAccount: Cooldown not reached"
			);
			delegatedAccesses[account][target][selector[i - 1]] = false;
			revokeProposalTimestamp[account][target][selector[i - 1]] = 0;
		}
		emit DelegateAccesses(account, target, selector, false);
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
	 * @dev Sets the revoke cooldown.
	 * @param cooldown the new revoke cooldown.
	 */
	function setDelegateAccessRevokeCooldown(uint256 cooldown) external onlyRole(SETTER_ROLE) {
		emit SetDelegateAccessRevokeCooldown(delegatedAccessRevokeCooldown, cooldown);
		delegatedAccessRevokeCooldown = cooldown;
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
		require(contractAddress != address(0), "MultiAccount: create2 failed");
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
	 * @dev Deposits specific collateral into the specified account.
	 * @param collateral The address of the collateral to be deposited.
	 * @param account The address of the account to deposit funds into.
	 * @param amount The amount of funds to deposit.
	 */
	function depositForAccount(address collateral, address account, uint256 amount) external onlyOwner(account, msg.sender) whenNotPaused {
		IERC20Upgradeable(collateral).safeTransferFrom(msg.sender, address(this), amount);
		IERC20Upgradeable(collateral).safeApprove(symmioAddress, amount);
		ISymmio(symmioAddress).depositFor(collateral, account, amount);
		emit DepositForAccount(collateral, msg.sender, account, amount);
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
		require(success, "MultiAccount: admin call to PartyA failed");
		emit AdminPartyACall(partyA, data, success, returnData);
	}

	// ================ CALL MANAGEMENT FUNCTIONS ================
	/**
	 * @dev Send a call to symmio from partyA account.
	 * @param account The address of the account to execute the calls on behalf of.
	 * @param _callData The input calldata to pass by the call.
	 */
	function innerCall(address account, bytes memory _callData) internal {
		(bool _success, bytes memory _resultData) = ISymmioPartyA(account)._call(_callData);
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
		bool isOwner = owners[account] == msg.sender;
		for (uint8 i; i < _callDatas.length; i++) {
			bytes memory _callData = _callDatas[i];
			if (!isOwner) {
				require(_callData.length >= 4, "MultiAccount: Invalid call data");
				bytes4 functionSelector;
				assembly {
					functionSelector := mload(add(_callData, 0x20))
				}
				require(delegatedAccesses[account][msg.sender][functionSelector], "MultiAccount: Unauthorized access");
			}
			innerCall(account, _callData);
		}
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
