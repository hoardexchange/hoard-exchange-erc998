// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IERC20AndERC223.sol";
import "./interfaces/IERC998ERC20TopDown.sol";
import "./interfaces/IERC998ERC20TopDownEnumerable.sol";
import "./interfaces/IERC998ERC721BottomUp.sol";
import "./interfaces/IERC998ERC721TopDown.sol";
import "./interfaces/IERC998ERC721TopDownEnumerable.sol";
import "./interfaces/IERC998ERC1155TopDown.sol";
import "./interfaces/IERC998ERC1155TopDownEnumerable.sol";
import "./interfaces/StateHash.sol";

contract ComposableTopDown is
    ERC165,
    IERC721,
    IERC721Metadata,
    Ownable,
    IERC998ERC721TopDown,
    IERC998ERC721TopDownEnumerable,
    IERC998ERC20TopDown,
    IERC998ERC20TopDownEnumerable,
    IERC998ERC1155TopDown,
    IERC998ERC1155TopDownEnumerable,
    IERC1155Receiver,
    StateHash
{
    using Address for address;
    using Strings for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    // return this.rootOwnerOf.selector ^ this.rootOwnerOfChild.selector ^
    //   this.tokenOwnerOf.selector ^ this.ownerOfChild.selector;
    bytes4 constant ERC998_MAGIC_VALUE = 0xcd740db5;
    bytes32 constant ERC998_MAGIC_VALUE_32 = 0xcd740db500000000000000000000000000000000000000000000000000000000;

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event NewBaseURI(string baseURI);

    // Token name
    string public name;

    // Token symbol
    string public symbol;

    string public baseURI;

    uint256 tokenCount = 0;

    // tokenId => token owner
    mapping(uint256 => address) private tokenIdToTokenOwner;

    // tokenId => last state hash indicator
    mapping(uint256 => uint256) private tokenIdToStateHash;

    // root token owner address => (tokenId => approved address)
    mapping(address => mapping(uint256 => address))
        private rootOwnerAndTokenIdToApprovedAddress;

    // token owner address => token count
    mapping(address => uint256) private tokenOwnerToTokenCount;

    // token owner => (operator address => bool)
    mapping(address => mapping(address => bool)) private tokenOwnerToOperators;

    constructor(string memory name_, string memory symbol_) Ownable() {
        name = name_;
        symbol = symbol_;
    }

    function safeMint(address _to) external virtual returns (uint256) {
        require(_to != address(0), "CTD: _to zero address");
        tokenCount++;
        uint256 tokenCount_ = tokenCount;
        tokenIdToTokenOwner[tokenCount_] = _to;
        tokenOwnerToTokenCount[_to]++;
        tokenIdToStateHash[tokenCount] = uint256(keccak256(abi.encodePacked(address(this), tokenCount)));

        emit Transfer(address(0), _to, tokenCount_);
        require(_checkOnERC721Received(address(0), _to, tokenCount_, ""), "CTD: non ERC721Receiver");
        return tokenCount_;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        require(tokenIdToTokenOwner[tokenId] != address(0), "CTD: URI does not exist");
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json")) : "";
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        baseURI = baseURI_;
        emit NewBaseURI(baseURI_);
    }

    //from zepellin ERC721Receiver.sol
    //old version
    bytes4 constant ERC721_RECEIVED_OLD = 0xf0b9e5ba;
    //new version
    bytes4 constant ERC721_RECEIVED_NEW = 0x150b7a02;
    //erc1155 zepellin ERC721Receiver.sol
    bytes4 constant ERC1155_RECEIVED_SINGLE = 0xf23a6e61;
    bytes4 constant ERC1155_RECEIVED_BATCH = 0xbc197c81;

    bytes4 constant ALLOWANCE = bytes4(keccak256("allowance(address,address)"));
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
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender],
            "CTD: approve msg.sender not owner"
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
        tokenOwnerToOperators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
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
                    msg.sender,
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
                    msg.sender,
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

        if (msg.sender != _from) {
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
                tokenOwnerToOperators[_from][msg.sender] ||
                    rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId] ==
                    msg.sender,
                "CTD: _transferFrom msg.sender not approved"
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
            _from == msg.sender ||
                IERC721(_childContract).isApprovedForAll(_from, msg.sender) ||
                IERC721(_childContract).getApproved(_childTokenId) ==
                msg.sender,
            "CTD: getChild msg.sender not approved"
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
        receiveChild(_from, tokenId, msg.sender, _childTokenId);
        require(
            IERC721(msg.sender).ownerOf(_childTokenId) != address(0),
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
        receiveChild(_from, tokenId, msg.sender, _childTokenId);
        require(
            IERC721(msg.sender).ownerOf(_childTokenId) != address(0),
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
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][tokenId] ==
                msg.sender,
            "CTD: _transferChild msg.sender not eligible"
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
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, _data) returns (bytes4 retval) {
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
            uint256 rootStateHash = tokenIdToStateHash[rootId];
            uint256 childStateHash = tokenIdToStateHash[_childTokenId];
            tokenIdToStateHash[rootId] = uint256(keccak256(abi.encodePacked(rootStateHash, _tokenId, _childContract, childStateHash)));
            tokenIdToStateHash[_childTokenId] = uint256(keccak256(abi.encodePacked(rootStateHash, _childTokenId, _childContract, childStateHash)));
        } else {
            tokenIdToStateHash[rootId] = uint256(keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _childContract, _childTokenId)));
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
            tokenIdToStateHash[rootId] = uint256(keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _childContract, tokenIdToStateHash[_childTokenId])));
        } else {
            tokenIdToStateHash[rootId] = uint256(keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _childContract, _childTokenId)));
        }
        emit ReceivedChild(_from, _tokenId, _childContract, _childTokenId);
    }

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
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] ==
                msg.sender,
            "CTD: transferERC20 msg.sender not eligible"
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
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId] ==
                msg.sender,
            "CTD: transferERC223 msg.sender not eligible"
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
            tx.origin != msg.sender,
            "CTD: tokenFallback msg.sender is not a contract"
        );
        uint256 tokenId = _parseTokenId(_data);
        erc20Received(_from, tokenId, msg.sender, _value);
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
        bool allowed = _from == msg.sender;
        if (!allowed) {
            bytes memory callData =
                abi.encodeWithSelector(ALLOWANCE, _from, msg.sender);
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
        tokenIdToStateHash[rootId] = uint256(keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _erc20Contract, erc20Balance + _value)));
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
            tokenIdToStateHash[rootId] = uint256(keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _tokenId, _erc20Contract, newERC20Balance)));
        }
        emit TransferERC20(_tokenId, _to, _erc20Contract, _value);
    }


    ////////////////////////////////////////////////////////
    // ERC998ERC1155 and ERC998ERC1155Enumerable implementation
    ////////////////////////////////////////////////////////

    // tokenId => erc1155 contract
    mapping(uint256 => EnumerableSet.AddressSet) private erc1155Contracts;

    // tokenId => (erc1155 contract => array of erc1155 tokens)
    mapping(uint256 => mapping(address => EnumerableSet.UintSet))
        private erc1155Tokens;

    // tokenId => (erc1155 contract => (childToken => balance))
    mapping(uint256 => mapping(address => mapping(uint256 => uint256)))
        private erc1155Balances;


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
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_fromTokenId] ==
                msg.sender,
            "CTD: transferERC223 msg.sender not eligible"
        );
        uint256 newBalance = removeERC1155(_fromTokenId, _erc1155Contract, _childTokenId, _amount);
        uint256 rootId = _localRootId(_fromTokenId);
        tokenIdToStateHash[rootId] = uint256(keccak256(abi.encodePacked(tokenIdToStateHash[rootId], _fromTokenId, _erc1155Contract, _childTokenId, newBalance)));
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
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                rootOwnerAndTokenIdToApprovedAddress[rootOwner][_fromTokenId] ==
                msg.sender,
            "CTD: transferERC223 msg.sender not eligible"
        );
        uint256 rootId = _localRootId(_fromTokenId);
        uint256 _newStateHash = tokenIdToStateHash[rootId];
        for (uint256 i = 0; i < _childTokenIds.length; ++i) {
            uint256 _newBalance = removeERC1155(_fromTokenId, _erc1155Contract, _childTokenIds[i], _amounts[i]);
            _newStateHash = uint256(keccak256(abi.encodePacked(_newStateHash, _fromTokenId, _erc1155Contract, _childTokenIds[i], _newBalance)));
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
        uint256 erc1155Balance = erc1155Balances[tokenId][msg.sender][_childTokenId];
        if (erc1155Balance == 0) {
            if (erc1155Tokens[tokenId][msg.sender].length() == 0) {
                erc1155Contracts[tokenId].add(msg.sender);
            }
            erc1155Tokens[tokenId][msg.sender].add(_childTokenId);
        }
        erc1155Balances[tokenId][msg.sender][_childTokenId] = erc1155Balance + _amount;
        uint256 rootId = _localRootId(tokenId);
        tokenIdToStateHash[rootId] = uint256(keccak256(abi.encodePacked(tokenIdToStateHash[rootId], tokenId, msg.sender, _childTokenId, erc1155Balance + _amount)));
        emit ReceivedErc1155(_from, tokenId, msg.sender, _childTokenId, _amount);
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
        uint256 erc1155ContractsLength = erc1155Tokens[tokenId][msg.sender].length();
        uint256 rootId = _localRootId(tokenId);
        uint256 _newStateHash = tokenIdToStateHash[rootId];
        for (uint256 i = 0; i < _childTokenIds.length; ++i) {
            uint256 erc1155Balance = erc1155Balances[tokenId][msg.sender][_childTokenIds[i]];
            if (erc1155Balance == 0) {
                if (erc1155ContractsLength == 0) {
                    erc1155Contracts[tokenId].add(msg.sender);
                    erc1155ContractsLength = 1;
                }
                erc1155Tokens[tokenId][msg.sender].add(_childTokenIds[i]);
            }
            erc1155Balances[tokenId][msg.sender][_childTokenIds[i]] = erc1155Balance + _amounts[i];
            _newStateHash = uint256(keccak256(abi.encodePacked(_newStateHash, tokenId, msg.sender, _childTokenIds[i], erc1155Balance + _amounts[i])));
        }
        tokenIdToStateHash[rootId] = _newStateHash;
        emit ReceivedBatchErc1155(_from, tokenId, msg.sender, _childTokenIds, _amounts);
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


    ////////////////////////////////////////////////////////
    // ERC165 implementation
    ////////////////////////////////////////////////////////

    /**
     * @dev See {IERC165-supportsInterface}.
     * The interface id 0x1bc995e4 is added. The spec claims it to be the interface id of IERC998ERC721TopDown.
     * But it is not.
     * It is added anyway in case some contract checks it being compliant with the spec.
     */
    function supportsInterface(bytes4 interfaceId) public view override(IERC165,ERC165) returns (bool) {
        return interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC721Metadata).interfaceId
            || interfaceId == type(IERC998ERC721TopDown).interfaceId
            || interfaceId == type(IERC998ERC721TopDownEnumerable).interfaceId
            || interfaceId == type(IERC998ERC20TopDown).interfaceId
            || interfaceId == type(IERC998ERC20TopDownEnumerable).interfaceId
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

    function stateHash(uint256 tokenId) external view override returns (uint256) {
        uint256 _stateHash = tokenIdToStateHash[tokenId];
        require(_stateHash > 0, "CTD: stateHash of _tokenId is zero");
        return _stateHash;
    }

    /**
     * @dev See {safeTransferFrom}.
     * Check the state hash and call safeTransferFrom.
     */
    function safeCheckedTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint256 expectedStateHash
    ) external {
        require(expectedStateHash == tokenIdToStateHash[tokenId], "CTD: stateHash mismatch (1)");
        safeTransferFrom(from, to, tokenId);
    }

    /**
     * @dev See {transferFrom}.
     * Check the state hash and call transferFrom.
     */
    function checkedTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint256 expectedStateHash
    ) external {
        require(expectedStateHash == tokenIdToStateHash[tokenId], "CTD: stateHash mismatch (2)");
        transferFrom(from, to, tokenId);
    }

    /**
     * @dev See {safeTransferFrom}.
     * Check the state hash and call safeTransferFrom.
     */
    function safeCheckedTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint256 expectedStateHash,
        bytes calldata data
    ) external {
        require(expectedStateHash == tokenIdToStateHash[tokenId], "CTD: stateHash mismatch (3)");
        safeTransferFrom(from, to, tokenId, data);
    }

}
