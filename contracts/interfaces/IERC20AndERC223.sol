// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IERC20AndERC223 {
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool success);

    function transfer(address to, uint256 value)
        external
        returns (bool success);

    function transfer(
        address to,
        uint256 value,
        bytes memory data
    ) external returns (bool success);

    function allowance(address _owner, address _spender)
        external
        view
        returns (uint256 remaining);
}
