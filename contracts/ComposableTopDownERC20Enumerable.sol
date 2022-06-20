// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IERC20AndERC223.sol";
import "./interfaces/IERC998ERC20TopDownEnumerable.sol";
import "./ComposableTopDown.sol";
import "./ComposableTopDownERC20.sol";

contract ComposableTopDownERC20Enumerable is
    ComposableTopDownERC20,
    IERC998ERC20TopDownEnumerable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    // tokenId => token contract
    mapping(uint256 => EnumerableSet.AddressSet) erc20Contracts;

    function _beforeERC20Received(
        address /*_from*/,
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) internal virtual override {
        if (erc20Balances[_tokenId][_erc20Contract] == 0 && _value > 0) {
            require(erc20Contracts[_tokenId].add(_erc20Contract), "CTD: erc20Received: erc20Contracts add _erc20Contract");
        }
    }

    function _beforeRemoveERC20(
        uint256 _tokenId,
        address /*_to*/,
        address _erc20Contract,
        uint256 _value
    ) internal virtual override {
        if (erc20Balances[_tokenId][_erc20Contract] == _value) {
            // the new balance is 0, so the ERC20 contract is removed
            require(erc20Contracts[_tokenId].remove(_erc20Contract), "CTD: removeERC20: erc20Contracts remove _erc20Contract");
        }
    }

    function erc20ContractByIndex(uint256 _tokenId, uint256 _index)
        external
        view
        override
        returns (address)
    {
        return erc20Contracts[_tokenId].at(_index);
    }

    function totalERC20Contracts(uint256 _tokenId)
        external
        view
        override
        returns (uint256)
    {
        return erc20Contracts[_tokenId].length();
    }

    function supportsInterface(bytes4 interfaceId) public virtual view override(ComposableTopDownERC20) returns (bool) {
        return interfaceId == type(IERC998ERC20TopDownEnumerable).interfaceId
            || ComposableTopDownERC20.supportsInterface(interfaceId);
    }
}
