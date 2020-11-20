// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IShareToken {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function mint(
        address account,
        uint256 amount,
        uint256 insurance
    ) external;

    function burn(address account, uint256 amount) external;
}
