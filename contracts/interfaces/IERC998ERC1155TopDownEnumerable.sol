// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IERC998ERC1155TopDownEnumerable {
    function totalERC1155Contracts(uint256 _tokenId)
        external
        view
        returns (uint256);

    function erc1155ContractByIndex(uint256 _tokenId, uint256 _index)
        external
        view
        returns (address);

    function totalERC1155Tokens(uint256 _tokenId, address _erc1155Contract)
        external
        view
        returns (uint256);

    function erc1155TokenByIndex(
        uint256 _tokenId,
        address _erc1155Contract,
        uint256 _index
    ) external view returns (uint256 erc1155TokenId);
}
