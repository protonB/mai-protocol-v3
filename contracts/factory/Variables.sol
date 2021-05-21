// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

contract Variables is Initializable, OwnableUpgradeable {
    bytes32 internal _reserved1;
    address internal _symbolService;
    address internal _vault;
    int256 internal _vaultFeeRate;

    event SetVaultFeeRate(int256 prevFeeRate, int256 newFeeRate);
    event SetVault(address previousVault, address newVault);
    event SetRewardDistributor(address previousRewardDistributor, address newRewardDistributor);

    function __Variables_init(
        address symbolService_,
        address vault_,
        int256 vaultFeeRate_
    ) internal initializer {
        require(symbolService_ != address(0), "invalid symbol service address");
        require(vault_ != address(0), "invalid vault address");
        require(vaultFeeRate_ >= 0, "negative vault fee rate");

        _symbolService = symbolService_;
        _vault = vault_;
        _vaultFeeRate = vaultFeeRate_;
    }

    /**
     * @notice Get the address of the vault
     * @return address The address of the vault
     */
    function getVault() public view returns (address) {
        return _vault;
    }

    /**
     * @notice Get the vault fee rate
     * @return int256 The vault fee rate
     */
    function getVaultFeeRate() public view returns (int256) {
        return _vaultFeeRate;
    }

    /**
     * @notice  Set the vault address. Can only called by owner.
     *
     * @param   newVault    The new value of the vault fee rate
     */
    function setVault(address newVault) external onlyOwner {
        require(_vault != newVault, "new vault is already current vault");
        emit SetVault(_vault, newVault);
        _vault = newVault;
    }

    /**
     * @notice  Set the vault fee rate. Can only called by owner.
     *
     * @param   newVaultFeeRate The new value of the vault fee rate
     */
    function setVaultFeeRate(int256 newVaultFeeRate) external onlyOwner {
        require(newVaultFeeRate >= 0, "negative vault fee rate");
        require(newVaultFeeRate != _vaultFeeRate, "unchanged vault fee rate");

        emit SetVaultFeeRate(_vaultFeeRate, newVaultFeeRate);
        _vaultFeeRate = newVaultFeeRate;
    }

    /**
     * @notice Get the address of the access controller. It's always its own address.
     *
     * @return address The address of the access controller.
     */
    function getAccessController() public view returns (address) {
        return address(this);
    }

    /**
     * @notice  Get the address of the symbol service.
     *
     * @return  Address The address of the symbol service.
     */
    function getSymbolService() public view returns (address) {
        return _symbolService;
    }

    /**
     * @notice  Get the address of the mcb token.
     * @dev     [ConfirmBeforeDeployment]
     *
     * @return  Address The address of the mcb token.
     */
    function getMCBToken() public pure returns (address) {
        // const MCB token
        // return address(0x83487dF1fA9C62130893A889578DFA7e2EAB9eFf);
        // TODO: test only
        return address(0x3FA06FBBD051ef8185Df9191ae1dEBddcEE8efAd);
        // kovan
        // return address(0xA0A45F2B616a740C3C7a7fF69Be893f61E6455E3);
        // bsc testnet, heco testnet
        // return address(0x9CaDa02fC03671EA66BaAC7929Cb769214621947);
    }
}
