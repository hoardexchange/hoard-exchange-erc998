// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IERC20AndERC223.sol";
import "./interfaces/IERC998ERC20TopDown.sol";
import "./interfaces/IERC998ERC20TopDownEnumerable.sol";
import "./ComposableTopDown.sol";

contract ComposableTopDownERC20 is
    ComposableTopDown,
    IERC998ERC20TopDown,
    IERC998ERC20TopDownEnumerable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    ////////////////////////////////////////////////////////
    // ERC998ERC223 and ERC998ERC223Enumerable implementation
    ////////////////////////////////////////////////////////

    // tokenId => token contract
    mapping(uint256 => EnumerableSet.AddressSet) erc20Contracts;

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
        require(
            rootOwner == _msgSender() ||
                tokenOwnerToOperators[rootOwner][_msgSender()] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] ==
                _msgSender(),
            "CTD: transferERC20 sender is not eligible"
        );
        removeERC20(_tokenId, _to, _erc20Contract, _value);
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
        require(
            rootOwner == _msgSender() ||
                tokenOwnerToOperators[rootOwner][_msgSender()] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] ==
                _msgSender(),
            "CTD: transferERC223 sender is not eligible"
        );
        removeERC20(_tokenId, _to, _erc223Contract, _value);
        require(
            IERC20AndERC223(_erc223Contract).transfer(_to, _value, _data),
            "CTD: transferERC223 transfer failed"
        );
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
        require(
            tx.origin != _msgSender(),
            "CTD: tokenFallback sender is not a contract"
        );
        uint256 tokenId = _parseTokenId(_data);
        erc20Received(_from, tokenId, _msgSender(), _value);
    }

    function balanceOfERC20(uint256 _tokenId, address _erc20Contract)
        external
        view
        override
        returns (uint256)
    {
        return erc20Balances[_tokenId][_erc20Contract];
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

    // this contract has to be approved first by _erc20Contract
    function getERC20(
        address _from,
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) public override {
        bool allowed = _from == _msgSender();
        if (!allowed) {
            bytes memory callData =
                abi.encodeWithSelector(ALLOWANCE, _from, _msgSender());
            (bool callSuccess, bytes memory data) =
                _erc20Contract.staticcall(callData);
            require(
                callSuccess,
                "CTD: getERC20 allowance failed"
            );
            uint256 remaining;
            assembly {
                remaining := mload(add(data, 0x20))
            }
            require(
                remaining >= _value,
                "CTD: getERC20 value greater than remaining"
            );
            allowed = true;
        }
        require(allowed, "CTD: getERC20 not allowed to getERC20");
        erc20Received(_from, _tokenId, _erc20Contract, _value);
        require(
            IERC20AndERC223(_erc20Contract).transferFrom(
                _from,
                address(this),
                _value
            ),
            "CTD: getERC20 transfer failed"
        );
    }

    function erc20Received(
        address _from,
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) internal {
        require(
            tokenIdToTokenOwner[_tokenId] != address(0),
            "CTD: erc20Received _tokenId does not exist"
        );
        if (_value == 0) {
            return;
        }
        uint256 erc20Balance = erc20Balances[_tokenId][_erc20Contract];
        if (erc20Balance == 0) {
            require(erc20Contracts[_tokenId].add(_erc20Contract), "CTD: erc20Received: erc20Contracts add _erc20Contract");
        }
        erc20Balances[_tokenId][_erc20Contract] += _value;
        uint256 rootId = _localRootId(_tokenId);
        tokenIdToStateHash[rootId] = keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _erc20Contract, erc20Balance + _value));
        emit ReceivedERC20(_from, _tokenId, _erc20Contract, _value);
    }

    function removeERC20(
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
        unchecked {
            // overflow already checked
            uint256 newERC20Balance = erc20Balance - _value;
            erc20Balances[_tokenId][_erc20Contract] = newERC20Balance;
            if (newERC20Balance == 0) {
                require(erc20Contracts[_tokenId].remove(_erc20Contract), "CTD: removeERC20: erc20Contracts remove _erc20Contract");
            }
            uint256 rootId = _localRootId(_tokenId);
            tokenIdToStateHash[rootId] = keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _erc20Contract, newERC20Balance));
        }
        emit TransferERC20(_tokenId, _to, _erc20Contract, _value);
    }


    function supportsInterface(bytes4 interfaceId) public virtual view override(ComposableTopDown) returns (bool) {
        return interfaceId == type(IERC998ERC20TopDown).interfaceId
            || interfaceId == type(IERC998ERC20TopDownEnumerable).interfaceId
            || ComposableTopDown.supportsInterface(interfaceId);
    }
}
