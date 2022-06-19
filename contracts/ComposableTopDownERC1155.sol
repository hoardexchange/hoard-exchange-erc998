// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IERC998ERC1155TopDown.sol";
import "./interfaces/IERC998ERC1155TopDownEnumerable.sol";
import "./ComposableTopDown.sol";

contract ComposableTopDownERC1155 is
    ComposableTopDown,
    IERC998ERC1155TopDown,
    IERC998ERC1155TopDownEnumerable,
    IERC1155Receiver
{
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    //erc1155 zepellin ERC721Receiver.sol
    bytes4 constant ERC1155_RECEIVED_SINGLE = 0xf23a6e61;
    bytes4 constant ERC1155_RECEIVED_BATCH = 0xbc197c81;

    // tokenId => erc1155 contract
    mapping(uint256 => EnumerableSet.AddressSet) internal erc1155Contracts;

    // tokenId => (erc1155 contract => array of erc1155 tokens)
    mapping(uint256 => mapping(address => EnumerableSet.UintSet))
        internal erc1155Tokens;

    // tokenId => (erc1155 contract => (childToken => balance))
    mapping(uint256 => mapping(address => mapping(uint256 => uint256)))
        internal erc1155Balances;


    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFromERC1155(
        uint256 _fromTokenId,
        address _to,
        address _erc1155Contract,
        uint256 _childTokenId,
        uint256 _amount,
        bytes memory _data
    ) public override {
        require(
            _to != address(0),
            "CTD: transferERC1155 _to zero address"
        );
        address rootOwner = address(uint160(uint256(rootOwnerOf(_fromTokenId))));
        require(
            rootOwner == _msgSender() ||
                tokenOwnerToOperators[rootOwner][_msgSender()] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_fromTokenId] ==
                _msgSender(),
            "CTD: transferERC223 sender is not eligible"
        );
        uint256 newBalance = removeERC1155(_fromTokenId, _erc1155Contract, _childTokenId, _amount);
        uint256 rootId = _localRootId(_fromTokenId);
        tokenIdToStateHash[rootId] = keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _fromTokenId, _erc1155Contract, _childTokenId, newBalance));
        emit TransferERC1155(_fromTokenId, _to, _erc1155Contract, _childTokenId, _amount);
        IERC1155(_erc1155Contract).safeTransferFrom(address(this), _to, _childTokenId, _amount, _data);
    }


    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     */
    function safeBatchTransferFromERC1155(
        uint256 _fromTokenId,
        address _to,
        address _erc1155Contract,
        uint256[] memory _childTokenIds,
        uint256[] memory _amounts,
        bytes memory _data
    ) public override {
        require(
            _childTokenIds.length == _amounts.length,
            "CTD: batchTransferERC1155 childTokenIds and amounts length mismatch"
        );
        require(
            _to != address(0),
            "CTD: batchTransferERC1155 _to zero address"
        );
        address rootOwner = address(uint160(uint256(rootOwnerOf(_fromTokenId))));
        require(
            rootOwner == _msgSender() ||
                tokenOwnerToOperators[rootOwner][_msgSender()] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_fromTokenId] ==
                _msgSender(),
            "CTD: transferERC223 sender is not eligible"
        );
        uint256 rootId = _localRootId(_fromTokenId);
        bytes32 _newStateHash = tokenIdToStateHash[rootId];
        for (uint256 i = 0; i < _childTokenIds.length; ++i) {
            uint256 _newBalance = removeERC1155(_fromTokenId, _erc1155Contract, _childTokenIds[i], _amounts[i]);
            _newStateHash = keccak256(abi.encodePacked(_newStateHash, _fromTokenId, _erc1155Contract, _childTokenIds[i], _newBalance));
        }
        tokenIdToStateHash[rootId] = _newStateHash;
        emit BatchTransferERC1155(_fromTokenId, _to, _erc1155Contract, _childTokenIds, _amounts);
        IERC1155(_erc1155Contract).safeBatchTransferFrom(address(this), _to, _childTokenIds, _amounts, _data);
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     */
    function balanceOfERC1155(uint256 _tokenId, address _erc1155Contract, uint256 childTokenId)
        external
        view
        override
        returns (uint256)
    {
        return erc1155Balances[_tokenId][_erc1155Contract][childTokenId];
    }


    /**
     * @dev See {IERC1155-balanceOf}.
     */
    function balanceOfBatchERC1155(uint256[] memory _tokenIds, address _erc1155Contract, uint256[] memory childTokenIds)
        external
        view
        override
        returns (uint256[] memory)
    {
        require(_tokenIds.length == childTokenIds.length, "CTD: batchTransferERC1155 childTokenIds and tokenIds length mismatch");

        uint256[] memory batchBalances = new uint256[](_tokenIds.length);

        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            batchBalances[i] = erc1155Balances[_tokenIds[i]][_erc1155Contract][childTokenIds[i]];
        }

        return batchBalances;
    }


    /**
     * @dev See {IERC1155Receiver-onERC1155Received}.
     */
    function onERC1155Received(
        address,
        address _from,
        uint256 _childTokenId,
        uint256 _amount,
        bytes calldata _data
    ) external override returns (bytes4) {
        require(
            _data.length > 0,
            "CTD: onERC1155Received _data must contain the uint256 tokenId to transfer the child token to"
        );
        // convert up to 32 bytes of _data to uint256, owner nft tokenId passed as uint in bytes
        uint256 tokenId = _parseTokenId(_data);
        require(
            tokenIdToTokenOwner[tokenId] != address(0),
            "CTD: onERC1155Received tokenId does not exist."
        );
        uint256 erc1155Balance = erc1155Balances[tokenId][_msgSender()][_childTokenId];
        if (erc1155Balance == 0) {
            if (erc1155Tokens[tokenId][_msgSender()].length() == 0) {
                erc1155Contracts[tokenId].add(_msgSender());
            }
            erc1155Tokens[tokenId][_msgSender()].add(_childTokenId);
        }
        erc1155Balances[tokenId][_msgSender()][_childTokenId] = erc1155Balance + _amount;
        uint256 rootId = _localRootId(tokenId);
        tokenIdToStateHash[rootId] = keccak256(abi.encodePacked(tokenIdToStateHash[rootId], tokenId, _msgSender(), _childTokenId, erc1155Balance + _amount));
        emit ReceivedErc1155(_from, tokenId, _msgSender(), _childTokenId, _amount);
        return ERC1155_RECEIVED_SINGLE;
    }


    /**
     * @dev See {IERC1155Receiver-onERC1155Received}.
     */
    function onERC1155BatchReceived(
        address,
        address _from,
        uint256[] calldata _childTokenIds,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external override returns (bytes4) {
        require(
            _data.length > 0,
            "CTD: onERC1155BatchReceived _data must contain the uint256 tokenId to transfer the child token to"
        );
        require(
            _childTokenIds.length == _amounts.length,
            "CTD: onERC1155BatchReceived _childTokenIds and _amounts lengths mismatch"
        );
        // convert up to 32 bytes of _data to uint256, owner nft tokenId passed as uint in bytes
        uint256 tokenId = _parseTokenId(_data);
        require(
            tokenIdToTokenOwner[tokenId] != address(0),
            "CTD: onERC1155BatchReceived tokenId does not exist."
        );
        uint256 erc1155ContractsLength = erc1155Tokens[tokenId][_msgSender()].length();
        uint256 rootId = _localRootId(tokenId);
        bytes32 _newStateHash = tokenIdToStateHash[rootId];
        for (uint256 i = 0; i < _childTokenIds.length; ++i) {
            uint256 erc1155Balance = erc1155Balances[tokenId][_msgSender()][_childTokenIds[i]];
            if (erc1155Balance == 0) {
                if (erc1155ContractsLength == 0) {
                    erc1155Contracts[tokenId].add(_msgSender());
                    erc1155ContractsLength = 1;
                }
                erc1155Tokens[tokenId][_msgSender()].add(_childTokenIds[i]);
            }
            erc1155Balances[tokenId][_msgSender()][_childTokenIds[i]] = erc1155Balance + _amounts[i];
            _newStateHash = keccak256(abi.encodePacked(_newStateHash, tokenId, _msgSender(), _childTokenIds[i], erc1155Balance + _amounts[i]));
        }
        tokenIdToStateHash[rootId] = _newStateHash;
        emit ReceivedBatchErc1155(_from, tokenId, _msgSender(), _childTokenIds, _amounts);
        return ERC1155_RECEIVED_BATCH;
    }


    function removeERC1155(
        uint256 _tokenId,
        address _erc1155Contract,
        uint256 _childTokenId,
        uint256 _amount
    ) internal returns (uint256) {
        if (_amount == 0) {
            return erc1155Balances[_tokenId][_erc1155Contract][_childTokenId];
        }
        uint256 erc1155Balance = erc1155Balances[_tokenId][_erc1155Contract][_childTokenId];
        require(
            erc1155Balance >= _amount,
            "CTD: removeERC1155 value not enough"
        );
        uint256 newERC1155Balance = erc1155Balance - _amount;
        erc1155Balances[_tokenId][_erc1155Contract][_childTokenId] = newERC1155Balance;
        if (newERC1155Balance == 0) {
            if (erc1155Tokens[_tokenId][_erc1155Contract].length() == 1) {
                erc1155Contracts[_tokenId].remove(_erc1155Contract);
            }
            erc1155Tokens[_tokenId][_erc1155Contract].remove(_childTokenId);
        }
        return newERC1155Balance;
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

    function supportsInterface(bytes4 interfaceId) public virtual view override(IERC165, ComposableTopDown) returns (bool) {
        return interfaceId == type(IERC998ERC1155TopDown).interfaceId
            || interfaceId == type(IERC998ERC1155TopDownEnumerable).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId
            || ComposableTopDown.supportsInterface(interfaceId);
    }
}
