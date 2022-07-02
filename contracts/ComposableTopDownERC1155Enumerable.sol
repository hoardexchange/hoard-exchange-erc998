// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IERC998ERC1155TopDown.sol";
import "./interfaces/IERC998ERC1155TopDownEnumerable.sol";
import "./ComposableTopDown.sol";
import "./ComposableTopDownERC1155.sol";

contract ComposableTopDownERC1155Enumerable is
    ComposableTopDownERC1155,
    IERC998ERC1155TopDownEnumerable
{
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    // tokenId => erc1155 contract
    mapping(uint256 => EnumerableSet.AddressSet) internal erc1155Contracts;

    // tokenId => (erc1155 contract => array of erc1155 tokens)
    mapping(uint256 => mapping(address => EnumerableSet.UintSet))
        internal erc1155Tokens;


    function _beforeERC1155Received(
        address /* _operator */,
        address /* _from */,
        uint256 _tokenId,
        address _erc1155Contract,
        uint256[] memory _childTokenIds,
        uint256[] memory _amounts,
        bytes memory /* data */
    ) internal virtual override {
        uint256 childTokensReceptions = 0;
        for (uint256 i = 0; i < _childTokenIds.length; ++i) {
            if (erc1155Balances[_tokenId][_erc1155Contract][_childTokenIds[i]] == 0 && _amounts[i] > 0) {
                if (childTokensReceptions == 0 && erc1155Tokens[_tokenId][_erc1155Contract].length() == 0) {
                    erc1155Contracts[_tokenId].add(_erc1155Contract);
                }
                unchecked{
                    childTokensReceptions ++;
                }
                erc1155Tokens[_tokenId][_erc1155Contract].add(_childTokenIds[i]);
            }
        }
    }

    function _beforeRemoveERC1155(
        address /* _operator */,
        uint256 _tokenId,
        address /* _to */,
        address _erc1155Contract,
        uint256[] memory _childTokenIds,
        uint256[] memory _amounts,
        bytes memory /* data */
    ) internal virtual override {
        uint256 childTokensRemovals = 0;
        for (uint256 i = 0 ; i < _childTokenIds.length ; i ++) {
            if (erc1155Balances[_tokenId][_erc1155Contract][_childTokenIds[i]] == _amounts[i] && _amounts[i] > 0) {
                unchecked {
                    childTokensRemovals ++;
                }
                erc1155Tokens[_tokenId][_erc1155Contract].remove(_childTokenIds[i]);
            }
        }
        if (childTokensRemovals > 0 && erc1155Tokens[_tokenId][_erc1155Contract].length() == 0) {
            erc1155Contracts[_tokenId].remove(_erc1155Contract);
        }
    }

    function totalERC1155Contracts(uint256 _tokenId)
        external
        view
        override
        returns (uint256)
    {
        return erc1155Contracts[_tokenId].length();
    }

    function erc1155ContractByIndex(uint256 _tokenId, uint256 _index)
        external
        view
        override
        returns (address)
    {
        return erc1155Contracts[_tokenId].at(_index);
    }

    function totalERC1155Tokens(uint256 _tokenId, address _erc1155Contract)
        external
        view
        override
        returns (uint256)
    {
        return erc1155Tokens[_tokenId][_erc1155Contract].length();
    }

    function erc1155TokenByIndex(
        uint256 _tokenId,
        address _erc1155Contract,
        uint256 _index
    ) external view override returns (uint256 erc1155TokenId) {
        return erc1155Tokens[_tokenId][_erc1155Contract].at(_index);
    }

    function supportsInterface(bytes4 interfaceId) public virtual view override(ComposableTopDownERC1155) returns (bool) {
        return interfaceId == type(IERC998ERC1155TopDownEnumerable).interfaceId
            || ComposableTopDownERC1155.supportsInterface(interfaceId);
    }
}
