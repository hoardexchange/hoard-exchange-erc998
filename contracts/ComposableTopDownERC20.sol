// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IERC20AndERC223.sol";
import "./interfaces/IERC998ERC20TopDown.sol";
import "./ComposableTopDown.sol";

contract ComposableTopDownERC20 is
    ComposableTopDown,
    IERC998ERC20TopDown
{
    using EnumerableSet for EnumerableSet.AddressSet;

    // tokenId => (token contract => balance)
    mapping(uint256 => mapping(address => uint256)) erc20Balances;

    function transferERC20(
        uint256 _tokenId,
        address _to,
        address _erc20Contract,
        uint256 _value
    ) external override {
        require(
            _to != address(0),
            "CTD: transferERC20 _to zero address"
        );
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        address sender = _msgSender();
        require(
            rootOwner == sender ||
                tokenOwnerToOperators[rootOwner][sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] ==
                sender,
            "CTD: transferERC20 sender is not eligible"
        );
        _removeERC20(_tokenId, _to, _erc20Contract, _value);
        require(
            IERC20AndERC223(_erc20Contract).transfer(_to, _value),
            "CTD: transferERC20 transfer failed"
        );
    }

    // implementation of ERC 223
    function transferERC223(
        uint256 _tokenId,
        address _to,
        address _erc223Contract,
        uint256 _value,
        bytes memory _data
    ) external override {
        require(
            _to != address(0),
            "CTD: transferERC223 _to zero address"
        );
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        address sender = _msgSender();
        require(
            rootOwner == sender ||
                tokenOwnerToOperators[rootOwner][sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] ==
                sender,
            "CTD: transferERC223 sender is not eligible"
        );
        _removeERC20(_tokenId, _to, _erc223Contract, _value);
        require(
            IERC20AndERC223(_erc223Contract).transfer(_to, _value, _data),
            "CTD: transferERC223 transfer failed"
        );
    }

    function _removeERC20(
        uint256 _tokenId,
        address _to,
        address _erc20Contract,
        uint256 _value
    ) internal {
        if (_value == 0) {
            return;
        }
        uint256 erc20Balance = erc20Balances[_tokenId][_erc20Contract];
        require(
            erc20Balance >= _value,
            "CTD: removeERC20 value not enough"
        );

        _beforeRemoveERC20(_tokenId, _to, _erc20Contract, _value);

        uint256 newERC20Balance;
        unchecked {
            // overflow already checked
            newERC20Balance = erc20Balance - _value;
        }
        uint256 rootId = _localRootId(_tokenId);
        tokenIdToStateHash[rootId] = keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _erc20Contract, newERC20Balance));
        erc20Balances[_tokenId][_erc20Contract] = newERC20Balance;
        emit TransferERC20(_tokenId, _to, _erc20Contract, _value);

        _afterRemoveERC20(_tokenId, _to, _erc20Contract, _value);
    }

    function _beforeRemoveERC20(
        uint256 _tokenId,
        address _to,
        address _erc20Contract,
        uint256 _value
    ) internal virtual {}

    function _afterRemoveERC20(
        uint256 _tokenId,
        address _to,
        address _erc20Contract,
        uint256 _value
    ) internal virtual {}

    function balanceOfERC20(uint256 _tokenId, address _erc20Contract)
        external
        view
        override
        returns (uint256)
    {
        return erc20Balances[_tokenId][_erc20Contract];
    }

    // used by ERC 223
    function tokenFallback(
        address _from,
        uint256 _value,
        bytes memory _data
    ) external override {
        require(
            _data.length > 0,
            "CTD: tokenFallback empty _data"
        );
        address sender = _msgSender();
        require(
            tx.origin != sender,
            "CTD: tokenFallback sender is not a contract"
        );
        uint256 tokenId = _parseTokenId(_data);
        _erc20Received(_from, tokenId, sender, _value);
    }

    // this contract has to be approved first by _erc20Contract
    function getERC20(
        address _from,
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) public override {
        address sender = _msgSender();
        if (_from != sender) {
            try IERC20AndERC223(_erc20Contract).allowance(_from, sender) returns (uint256 remaining) {
                require(
                    remaining >= _value,
                    "CTD: getERC20 value greater than remaining"
                );
            } catch {
                revert("CTD: getERC20 allowance failed");
            }
        }
        _erc20Received(_from, _tokenId, _erc20Contract, _value);
        require(
            IERC20AndERC223(_erc20Contract).transferFrom(
                _from,
                address(this),
                _value
            ),
            "CTD: getERC20 transfer failed"
        );
    }

    function _erc20Received(
        address _from,
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) internal {
        require(
            tokenIdToTokenOwner[_tokenId] != address(0),
            "CTD: erc20Received _tokenId does not exist"
        );

        _beforeERC20Received(_from, _tokenId, _erc20Contract, _value);

        uint256 newErc20Balance = erc20Balances[_tokenId][_erc20Contract] + _value;
        erc20Balances[_tokenId][_erc20Contract] = newErc20Balance;
        uint256 rootId = _localRootId(_tokenId);
        tokenIdToStateHash[rootId] = keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _erc20Contract, newErc20Balance));
        emit ReceivedERC20(_from, _tokenId, _erc20Contract, _value);

        _afterERC20Received(_from, _tokenId, _erc20Contract, _value);
    }

    function _beforeERC20Received(
        address _from,
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) internal virtual {}

    function _afterERC20Received(
        address _from,
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) internal virtual {}

    function supportsInterface(bytes4 interfaceId) public virtual view override(ComposableTopDown) returns (bool) {
        return interfaceId == type(IERC998ERC20TopDown).interfaceId
            || ComposableTopDown.supportsInterface(interfaceId);
    }
}
