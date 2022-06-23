// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IERC998ERC721BottomUp.sol";
import "./interfaces/IERC998ERC721TopDown.sol";
import "./interfaces/IERC998ERC721TopDownEnumerable.sol";
import "./interfaces/StateHash.sol";
import "@openzeppelin/contracts/utils/Context.sol";

contract ComposableTopDown is
    Context,
    ERC165,
    IERC721,
    IERC998ERC721TopDown,
    IERC998ERC721TopDownEnumerable,
    StateHash
{
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    // return this.rootOwnerOf.selector ^ this.rootOwnerOfChild.selector ^
    //   this.tokenOwnerOf.selector ^ this.ownerOfChild.selector;
    bytes4 constant ERC998_MAGIC_VALUE = 0xcd740db5;
    bytes32 constant ERC998_MAGIC_VALUE_32 = 0xcd740db500000000000000000000000000000000000000000000000000000000;

    // tokenId => token owner
    mapping(uint256 => address) internal tokenIdToTokenOwner;

    // tokenId => last state hash indicator
    mapping(uint256 => bytes32) internal tokenIdToStateHash;

    // root token owner address => (tokenId => approved address)
    mapping(address => mapping(uint256 => address))
        internal rootOwnerAndTokenIdToApprovedAddress;

    // token owner address => token count
    mapping(address => uint256) private tokenOwnerToTokenCount;

    // token owner => (operator address => bool)
    mapping(address => mapping(address => bool)) internal tokenOwnerToOperators;

    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal virtual {
        _mint(to, tokenId);
        require(_checkOnERC721Received(address(0), to, tokenId, data), "CTD: non ERC721Receiver");
    }

    function _mint(address _to, uint256 tokenId) internal virtual {
        require(_to != address(0), "CTD: _to zero address");
        require(tokenId != 0, "CTD: zero tokenId is not supported");
        tokenIdToTokenOwner[tokenId] = _to;
        tokenOwnerToTokenCount[_to]++;
        tokenIdToStateHash[tokenId] = keccak256(abi.encodePacked(address(this), tokenId));

        emit Transfer(address(0), _to, tokenId);
    }

    //from zepellin ERC721Receiver.sol
    //old version
    bytes4 constant ERC721_RECEIVED_OLD = 0xf0b9e5ba;
    //new version
    bytes4 constant ERC721_RECEIVED_NEW = 0x150b7a02;

    bytes4 constant APPROVE = bytes4(keccak256("approve(address,uint256)"));
    bytes4 constant ROOT_OWNER_OF_CHILD =
        bytes4(keccak256("rootOwnerOfChild(address,uint256)"));

    ////////////////////////////////////////////////////////
    // ERC721 implementation
    ////////////////////////////////////////////////////////
    function rootOwnerOf(uint256 _tokenId)
        public
        view
        override
        returns (bytes32 rootOwner)
    {
        return rootOwnerOfChild(address(0), _tokenId);
    }

    // returns the owner at the top of the tree of composables
    // Use Cases handled:
    // Case 1: Token owner is this contract and token.
    // Case 2: Token owner is other top-down composable
    // Case 3: Token owner is other contract
    // Case 4: Token owner is user
    function rootOwnerOfChild(address _childContract, uint256 _childTokenId)
        public
        view
        override
        returns (bytes32 rootOwner)
    {
        address rootOwnerAddress;
        if (_childContract != address(0)) {
            (rootOwnerAddress, _childTokenId) = _ownerOfChild(
                _childContract,
                _childTokenId
            );
        } else {
            rootOwnerAddress = tokenIdToTokenOwner[_childTokenId];
            require(rootOwnerAddress != address(0), "CTD: ownerOf _tokenId zero address");
        }
        // Case 1: Token owner is this contract and token.
        while (rootOwnerAddress == address(this)) {
            (rootOwnerAddress, _childTokenId) = _ownerOfChild(
                rootOwnerAddress,
                _childTokenId
            );
        }
        bytes memory callData =
            abi.encodeWithSelector(
                ROOT_OWNER_OF_CHILD,
                address(this),
                _childTokenId
            );
        (bool callSuccess, bytes memory data) =
            rootOwnerAddress.staticcall(callData);
        if (callSuccess) {
            assembly {
                rootOwner := mload(add(data, 0x20))
            }
        }

        if (callSuccess == true && rootOwner & 0xffffffff00000000000000000000000000000000000000000000000000000000 == ERC998_MAGIC_VALUE_32) {
            // Case 2: Token owner is other top-down composable
            return rootOwner;
        } else {
            // Case 3: Token owner is other contract
            // Or
            // Case 4: Token owner is user
            assembly {
                rootOwner := or(ERC998_MAGIC_VALUE_32, rootOwnerAddress)
            }
        }
    }

    // returns the owner at the top of the tree of composables

    function ownerOf(uint256 _tokenId)
        public
        view
        override
        returns (address tokenOwner)
    {
        tokenOwner = tokenIdToTokenOwner[_tokenId];
        require(
            tokenOwner != address(0),
            "CTD: ownerOf _tokenId zero address"
        );
        return tokenOwner;
    }

    function balanceOf(address _tokenOwner)
        external
        view
        override
        virtual
        returns (uint256)
    {
        require(
            _tokenOwner != address(0),
            "CTD: balanceOf _tokenOwner zero address"
        );
        return tokenOwnerToTokenCount[_tokenOwner];
    }

    function approve(address _approved, uint256 _tokenId) external override virtual {
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        require(
            rootOwner == _msgSender() ||
                tokenOwnerToOperators[rootOwner][_msgSender()],
            "CTD: approve sender is not owner"
        );
        rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] = _approved;
        emit Approval(rootOwner, _approved, _tokenId);
    }

    function getApproved(uint256 _tokenId)
        public
        view
        override
        virtual
        returns (address)
    {
        address rootOwner = address(uint160(uint256(rootOwnerOf(_tokenId))));
        return rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId];
    }

    function setApprovalForAll(address _operator, bool _approved)
        external
        override
        virtual
    {
        require(
            _operator != address(0),
            "CTD: setApprovalForAll _operator zero address"
        );
        tokenOwnerToOperators[_msgSender()][_operator] = _approved;
        emit ApprovalForAll(_msgSender(), _operator, _approved);
    }

    function isApprovedForAll(address _owner, address _operator)
        external
        view
        override
        virtual
        returns (bool)
    {
        require(
            _owner != address(0),
            "CTD: isApprovedForAll _owner zero address"
        );
        require(
            _operator != address(0),
            "CTD: isApprovedForAll _operator zero address"
        );
        return tokenOwnerToOperators[_owner][_operator];
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public override virtual {
        _transferFrom(_from, _to, _tokenId);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public override virtual {
        _transferFrom(_from, _to, _tokenId);
        if (_to.isContract()) {
            bytes4 retval =
                IERC721Receiver(_to).onERC721Received(
                    _msgSender(),
                    _from,
                    _tokenId,
                    ""
                );
            require(
                retval == ERC721_RECEIVED_OLD || retval == ERC721_RECEIVED_NEW,
                "CTD: safeTransferFrom(3) onERC721Received invalid return value"
            );
        }
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) public override virtual {
        _transferFrom(_from, _to, _tokenId);
        if (_to.isContract()) {
            bytes4 retval =
                IERC721Receiver(_to).onERC721Received(
                    _msgSender(),
                    _from,
                    _tokenId,
                    _data
                );
            require(
                retval == ERC721_RECEIVED_OLD || retval == ERC721_RECEIVED_NEW,
                "CTD: safeTransferFrom(4) onERC721Received invalid return value"
            );
            rootOwnerOf(_tokenId);
        }
    }

    function _transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal {
        require(
            _from != address(0),
            "CTD: _transferFrom _from zero address"
        );
        require(
            tokenIdToTokenOwner[_tokenId] == _from,
            "CTD: _transferFrom _from not owner"
        );
        require(
            _to != address(0),
            "CTD: _transferFrom _to zero address"
        );

        if (_msgSender() != _from) {
            bytes memory callData =
                abi.encodeWithSelector(
                    ROOT_OWNER_OF_CHILD,
                    address(this),
                    _tokenId
                );
            (bool callSuccess, bytes memory data) = _from.staticcall(callData);
            if (callSuccess == true) {
                bytes32 rootOwner;
                assembly {
                    rootOwner := mload(add(data, 0x20))
                }
                require(
                    rootOwner & 0xffffffff00000000000000000000000000000000000000000000000000000000 != ERC998_MAGIC_VALUE_32,
                    "CTD: _transferFrom token is child of other top down composable"
                );
            }

            require(
                tokenOwnerToOperators[_from][_msgSender()] ||
                    rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId] ==
                    _msgSender(),
                "CTD: _transferFrom sender is not approved"
            );
        }

        // clear approval
        if (
            rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId] != address(0)
        ) {
            delete rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId];
            emit Approval(_from, address(0), _tokenId);
        }

        // remove and transfer token
        if (_from != _to) {
            assert(tokenOwnerToTokenCount[_from] > 0);
            tokenOwnerToTokenCount[_from]--;
            tokenIdToTokenOwner[_tokenId] = _to;
            tokenOwnerToTokenCount[_to]++;
        }
        emit Transfer(_from, _to, _tokenId);
    }

    ////////////////////////////////////////////////////////
    // ERC998ERC721 and ERC998ERC721Enumerable implementation
    ////////////////////////////////////////////////////////

    // tokenId => child contract
    mapping(uint256 => EnumerableSet.AddressSet) private childContracts;

    // tokenId => (child address => array of child tokens)
    mapping(uint256 => mapping(address => EnumerableSet.UintSet))
        private childTokens;

    // child address => childId => tokenId
    mapping(address => mapping(uint256 => uint256)) private childTokenOwner;

    function safeTransferChild(
        uint256 _fromTokenId,
        address _to,
        address _childContract,
        uint256 _childTokenId
    ) external override {
        _transferChild(_fromTokenId, _to, _childContract, _childTokenId);
        emit TransferChild(_fromTokenId, _to, _childContract, _childTokenId);
        IERC721(_childContract).safeTransferFrom(
            address(this),
            _to,
            _childTokenId
        );
    }

    function safeTransferChild(
        uint256 _fromTokenId,
        address _to,
        address _childContract,
        uint256 _childTokenId,
        bytes memory _data
    ) external override {
        _transferChild(_fromTokenId, _to, _childContract, _childTokenId);
        emit TransferChild(_fromTokenId, _to, _childContract, _childTokenId);
        IERC721(_childContract).safeTransferFrom(
            address(this),
            _to,
            _childTokenId,
            _data
        );
    }

    function transferChild(
        uint256 _fromTokenId,
        address _to,
        address _childContract,
        uint256 _childTokenId
    ) external override {
        _transferChild(_fromTokenId, _to, _childContract, _childTokenId);
        emit TransferChild(_fromTokenId, _to, _childContract, _childTokenId);
        //this is here to be compatible with cryptokitties and other old contracts that require being owner and approved
        // before transferring.
        //does not work with current standard which does not allow approving self, so we must let it fail in that case.
        bytes memory callData =
            abi.encodeWithSelector(APPROVE, this, _childTokenId);
        // solhint-disable-next-line avoid-low-level-calls
        _childContract.call(callData);

        IERC721(_childContract).transferFrom(address(this), _to, _childTokenId);
    }

    function transferChildToParent(
        uint256 _fromTokenId,
        address _toContract,
        uint256 _toTokenId,
        address _childContract,
        uint256 _childTokenId,
        bytes memory _data
    ) external override {
        _transferChild(
            _fromTokenId,
            _toContract,
            _childContract,
            _childTokenId
        );
        emit TransferChild(
            _fromTokenId,
            _toContract,
            _childContract,
            _childTokenId
        );
        IERC998ERC721BottomUp(_childContract).transferToParent(
            address(this),
            _toContract,
            _toTokenId,
            _childTokenId,
            _data
        );
    }

    // this contract has to be approved first in _childContract
    function getChild(
        address _from,
        uint256 _tokenId,
        address _childContract,
        uint256 _childTokenId
    ) external override {
        receiveChild(_from, _tokenId, _childContract, _childTokenId);
        require(
            _from == _msgSender() ||
                IERC721(_childContract).isApprovedForAll(_from, _msgSender()) ||
                IERC721(_childContract).getApproved(_childTokenId) ==
                _msgSender(),
            "CTD: getChild sender is not approved"
        );
        IERC721(_childContract).transferFrom(
            _from,
            address(this),
            _childTokenId
        );
        // a check for looped ownership chain
        rootOwnerOf(_tokenId);
    }

    function onERC721Received(
        address _from,
        uint256 _childTokenId,
        bytes calldata _data
    ) external returns (bytes4) {
        require(
            _data.length > 0,
            "CTD: onERC721Received(3) empty _data"
        );
        // convert up to 32 bytes of _data to uint256, owner nft tokenId passed as uint in bytes
        uint256 tokenId = _parseTokenId(_data);
        receiveChild(_from, tokenId, _msgSender(), _childTokenId);
        require(
            IERC721(_msgSender()).ownerOf(_childTokenId) != address(0),
            "CTD: onERC721Received(3) child token not owned"
        );
        // a check for looped ownership chain
        rootOwnerOf(tokenId);
        return ERC721_RECEIVED_OLD;
    }

    function onERC721Received(
        address,
        address _from,
        uint256 _childTokenId,
        bytes calldata _data
    ) external override returns (bytes4) {
        require(
            _data.length > 0,
            "CTD: onERC721Received(4) empty _data"
        );
        // convert up to 32 bytes of _data to uint256, owner nft tokenId passed as uint in bytes
        uint256 tokenId = _parseTokenId(_data);
        receiveChild(_from, tokenId, _msgSender(), _childTokenId);
        require(
            IERC721(_msgSender()).ownerOf(_childTokenId) != address(0),
            "CTD: onERC721Received(4) child token not owned"
        );
        // a check for looped ownership chain
        rootOwnerOf(tokenId);
        return ERC721_RECEIVED_NEW;
    }

    function childExists(address _childContract, uint256 _childTokenId)
        external
        view
        returns (bool)
    {
        uint256 tokenId = childTokenOwner[_childContract][_childTokenId];
        return tokenId != 0;
    }

    function totalChildContracts(uint256 _tokenId)
        external
        view
        override
        returns (uint256)
    {
        return childContracts[_tokenId].length();
    }

    function childContractByIndex(uint256 _tokenId, uint256 _index)
        external
        view
        override
        returns (address childContract)
    {
        return childContracts[_tokenId].at(_index);
    }

    function totalChildTokens(uint256 _tokenId, address _childContract)
        external
        view
        override
        returns (uint256)
    {
        return childTokens[_tokenId][_childContract].length();
    }

    function childTokenByIndex(
        uint256 _tokenId,
        address _childContract,
        uint256 _index
    ) external view override returns (uint256 childTokenId) {
        return childTokens[_tokenId][_childContract].at(_index);
    }

    function ownerOfChild(address _childContract, uint256 _childTokenId)
        external
        view
        override
        returns (bytes32 parentTokenOwner, uint256 parentTokenId)
    {
        parentTokenId = childTokenOwner[_childContract][_childTokenId];
        require(
            parentTokenId != 0,
            "CTD: ownerOfChild not found"
        );
        address parentTokenOwnerAddress = tokenIdToTokenOwner[parentTokenId];
        assembly {
            parentTokenOwner := or(ERC998_MAGIC_VALUE_32, parentTokenOwnerAddress)
        }

    }

    function _transferChild(
        uint256 _fromTokenId,
        address _to,
        address _childContract,
        uint256 _childTokenId
    ) internal {
        uint256 tokenId = childTokenOwner[_childContract][_childTokenId];
        require(
            tokenId != 0,
            "CTD: _transferChild _childContract _childTokenId not found"
        );
        require(
            tokenId == _fromTokenId,
            "CTD: _transferChild wrong tokenId found"
        );
        require(
            _to != address(0),
            "CTD: _transferChild _to zero address"
        );
        address rootOwner = address(uint160(uint256(rootOwnerOf(tokenId))));
        require(
            rootOwner == _msgSender() ||
                tokenOwnerToOperators[rootOwner][_msgSender()] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][tokenId] ==
                _msgSender(),
            "CTD: _transferChild sender is not eligible"
        );
        removeChild(tokenId, _childContract, _childTokenId);
    }

    function _ownerOfChild(address _childContract, uint256 _childTokenId)
        internal
        view
        returns (address parentTokenOwner, uint256 parentTokenId)
    {
        parentTokenId = childTokenOwner[_childContract][_childTokenId];
        require(
            parentTokenId != 0,
            "CTD: _ownerOfChild not found"
        );
        return (tokenIdToTokenOwner[parentTokenId], parentTokenId);
    }

    function _parseTokenId(bytes memory _data)
        internal
        pure
        returns (uint256 tokenId)
    {
        // convert up to 32 bytes of_data to uint256, owner nft tokenId passed as uint in bytes
        assembly {
            tokenId := mload(add(_data, 0x20))
        }
        if (_data.length < 32) {
            tokenId = tokenId >> (256 - _data.length * 8);
        }
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data)
        internal returns (bool)
    {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver(to).onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("CTD: non ERC721Receiver");
                } else {
                    // solhint-disable-next-line no-inline-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    function removeChild(
        uint256 _tokenId,
        address _childContract,
        uint256 _childTokenId
    ) internal {
        // remove child token
        uint256 lastTokenIndex =
            childTokens[_tokenId][_childContract].length() - 1;
        require(childTokens[_tokenId][_childContract].remove(_childTokenId), "CTD: removeChild: _childTokenId not found");
        delete childTokenOwner[_childContract][_childTokenId];

        // remove contract
        if (lastTokenIndex == 0) {
            require(childContracts[_tokenId].remove(_childContract), "CTD: removeChild: _childContract not found");
        }
        uint256 rootId = _localRootId(_tokenId);
        if (_childContract == address(this)) {
            bytes32 rootStateHash = tokenIdToStateHash[rootId];
            bytes32 childStateHash = tokenIdToStateHash[_childTokenId];
            tokenIdToStateHash[rootId] = keccak256(abi.encodePacked(rootStateHash, _tokenId, _childContract, childStateHash));
            tokenIdToStateHash[_childTokenId] = keccak256(abi.encodePacked(rootStateHash, _childTokenId, _childContract, childStateHash));
        } else {
            tokenIdToStateHash[rootId] = keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _childContract, _childTokenId));
        }
    }

    function receiveChild(
        address _from,
        uint256 _tokenId,
        address _childContract,
        uint256 _childTokenId
    ) internal {
        require(
            tokenIdToTokenOwner[_tokenId] != address(0),
            "CTD: receiveChild _tokenId does not exist."
        );
        require(
            childTokenOwner[_childContract][_childTokenId] != _tokenId,
            "CTD: receiveChild _childTokenId already received"
        );
        uint256 childTokensLength =
            childTokens[_tokenId][_childContract].length();
        if (childTokensLength == 0) {
            require(childContracts[_tokenId].add(_childContract), "CTD: receiveChild: add _childContract");
        }
        require(childTokens[_tokenId][_childContract].add(_childTokenId), "CTD: receiveChild: add _childTokenId");
        childTokenOwner[_childContract][_childTokenId] = _tokenId;
        uint256 rootId = _localRootId(_tokenId);
        if (_childContract == address(this)) {
            tokenIdToStateHash[rootId] = keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _childContract, tokenIdToStateHash[_childTokenId]));
        } else {
            tokenIdToStateHash[rootId] = keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _childContract, _childTokenId));
        }
        emit ReceivedChild(_from, _tokenId, _childContract, _childTokenId);
    }


    ////////////////////////////////////////////////////////
    // ERC165 implementation
    ////////////////////////////////////////////////////////

    /**
     * @dev See {IERC165-supportsInterface}.
     * The interface id 0x1bc995e4 is added. The spec claims it to be the interface id of IERC998ERC721TopDown.
     * But it is not.
     * It is added anyway in case some contract checks is being compliant with the spec.
     */
    function supportsInterface(bytes4 interfaceId) public virtual view override(IERC165,ERC165) returns (bool) {
        return interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC998ERC721TopDown).interfaceId
            || interfaceId == type(IERC998ERC721TopDownEnumerable).interfaceId
            || interfaceId == 0x1bc995e4
            || interfaceId == type(StateHash).interfaceId
            || super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////
    // Last State Hash
    ////////////////////////////////////////////////////////

    /**
     * @dev Returns tokenId of the root bundle. Local means that it does not traverse through foreign ERC998 contracts.
     */
    function _localRootId(uint256 tokenId) internal view returns (uint256) {
        while (tokenIdToTokenOwner[tokenId] == address(this)) {
            tokenId = childTokenOwner[address(this)][tokenId];
        }
        return tokenId;
    }

    function stateHash(uint256 tokenId) external view override returns (bytes32) {
        bytes32 _stateHash = tokenIdToStateHash[tokenId];
        require(_stateHash != 0, "CTD: stateHash of _tokenId is zero");
        return _stateHash;
    }
}
