// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./interfaces/IUnitagExternalTag.sol";
import "./interfaces/IUnitagV2.sol";
import "./library/UnitagLib.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard
 */
contract UnitagERC721TagBase is IUnitagExternalTag, Context, ERC165, IERC721Metadata {
    using Address for address;
    using Strings for uint256;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping(uint256 => uint256) internal _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping owner address to bound token count
    mapping(address => uint256) private _boundBalances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint256 private _tokenCounter;

    string private _baseUri;
    IUnitagV2 public immutable unitag;
    uint256 public immutable tagId;

    function _setURI(string memory uri_) internal {
        _baseUri = uri_;
    }

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_, string memory collectionName_, string memory tagName_, uint256 value, uint256 maxSupply, uint256 releasedSupply, address unitagV2_) {
        _name = name_;
        _symbol = symbol_;
        unitag = IUnitagV2(unitagV2_);
        tagId = unitag.setupTag(collectionName_, tagName_, value, maxSupply, releasedSupply);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IUnitagExternalTag).interfaceId || interfaceId == type(IERC721).interfaceId || interfaceId == type(IERC721Metadata).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IUnitagERC721TagBase-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override(IERC721, IUnitagExternalTag) returns (uint256) {
        require(owner != address(0), "UnitagERC721TagBase: address zero is not a valid owner");
        return _balances[owner];
    }

    /**
     * @dev See {IUnitagERC721TagBase-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        uint256 owner = _owners[tokenId];
        require(owner != 0, "UnitagERC721TagBase: invalid token ID");
        return address(uint160(owner));
    }

    /**
     * @dev See {IUnitagERC721TagBase-tokenOf}.
     */
    function tokenOf(uint256 tokenId) public view returns (address owner, bool isBinded) {
        uint256 ownerData = _owners[tokenId];
        require(ownerData != 0, "UnitagERC721TagBase: invalid token ID");
        owner = address(uint160(ownerData));
        isBinded = ownerData != (ownerData & type(uint160).max);
    }

    /**
     * @dev See {IUnitagERC721TagBaseMetadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IUnitagERC721TagBaseMetadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        return string(abi.encodePacked(_baseUri, tokenId.toString(), ".json"));
    }

    /**
     * @dev See {IUnitagERC721TagBase-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = UnitagERC721TagBase.ownerOf(tokenId);
        require(to != owner, "UnitagERC721TagBase: approval to current owner");

        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()), "UnitagERC721TagBase: approve caller is not token owner nor approved for all");

        _approve(to, tokenId);
    }

    /**
     * @dev See {IUnitagERC721TagBase-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        _requireMinted(tokenId);

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IUnitagERC721TagBase-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IUnitagERC721TagBase-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IUnitagERC721TagBase-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "UnitagERC721TagBase: caller is not token owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IUnitagERC721TagBase-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IUnitagERC721TagBase-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "UnitagERC721TagBase: caller is not token owner nor approved");
        _safeTransfer(from, to, tokenId, data);
    }

    function boundOf(address account) external view returns (uint256 amount) {
        amount = _boundBalances[account];
    }

    function bind(uint256 tokenId) external {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "UnitagERC721TagBase: caller is not token owner nor approved");
        uint256 ownerData = _owners[tokenId];
        _owners[tokenId] = (ownerData | (1 << 160));
        address owner = address(uint160(ownerData));
        uint256 boundBalance = _boundBalances[owner] + 1;
        _boundBalances[owner] = boundBalance;
        unitag.bindExternal(owner, tagId, 1);
        emit BoundSingle(_msgSender(), owner, tagId, tokenId);
        emit BalanceChanged(owner, _balances[owner] - boundBalance);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the UnitagERC721TagBase protocol to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onUnitagERC721TagBaseReceived}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "UnitagERC721TagBase: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != 0;
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        (address owner, bool isBinded) = UnitagERC721TagBase.tokenOf(tokenId);
        return (!isBinded && (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender));
    }

    function mint(address to, uint256 amount, bool bindImmediately) external onlyUnitag {
        uint256 ownerData = uint256(uint160(to));
        if (bindImmediately) ownerData |= (1 << 160);
        for (uint index = 0; index < amount; ++index) _safeMint(ownerData);

        if (bindImmediately) {
            _boundBalances[to] += amount;
            unitag.bindExternal(to, tagId, amount);
            emit BoundSingle(_msgSender(), to, tagId, amount);
        } else emit BalanceChanged(to, _balances[to] - _boundBalances[to]);
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onUnitagERC721TagBaseReceived}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(uint256 ownerData) private {
        address to = address(uint160(ownerData));
        require(to != address(0), "UnitagERC721TagBase: mint to the zero address");
        uint256 tokenId = _tokenCounter;
        _tokenCounter = tokenId + 1;

        _beforeTokenTransfer(address(0), to, tokenId);

        uint256 balance = _balances[to] + 1;
        _balances[to] = balance;
        _owners[tokenId] = ownerData;

        emit Transfer(address(0), to, tokenId);

        _afterTokenTransfer(address(0), to, tokenId);

        require(_checkOnERC721Received(address(0), to, tokenId, ""), "UnitagERC721TagBase: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = UnitagERC721TagBase.ownerOf(tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        uint256 balance = _balances[owner] - 1;
        _balances[owner] = balance;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);
        emit BalanceChanged(owner, balance - _boundBalances[owner]);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(UnitagERC721TagBase.ownerOf(tokenId) == from, "UnitagERC721TagBase: transfer from incorrect owner");
        require(to != address(0), "UnitagERC721TagBase: transfer to the zero address");

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        uint256 fromBalance = _balances[from] - 1;
        _balances[from] = fromBalance;
        uint256 toBalance = _balances[to] + 1;
        _balances[to] = toBalance;

        _owners[tokenId] = (_owners[tokenId] & (type(uint96).max << 160)) | uint256(uint160(to));

        emit Transfer(from, to, tokenId);
        emit BalanceChanged(from, fromBalance - _boundBalances[from]);
        emit BalanceChanged(to, toBalance - _boundBalances[to]);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(UnitagERC721TagBase.ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(address owner, address operator, bool approved) internal virtual {
        require(owner != operator, "UnitagERC721TagBase: approve to caller");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /**
     * @dev Reverts if the `tokenId` has not been minted yet.
     */
    function _requireMinted(uint256 tokenId) internal view virtual {
        require(_exists(tokenId), "UnitagERC721TagBase: invalid token ID");
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onUnitagERC721TagBaseReceived} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("UnitagERC721TagBase: transfer to non ERC721Receiver implementer");
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}

    modifier onlyUnitag() {
        require(_msgSender() == address(unitag), "UnitagERC721TagBase: only accept unitag caller");
        _;
    }
}
