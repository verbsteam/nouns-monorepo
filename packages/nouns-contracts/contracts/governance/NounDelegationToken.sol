// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { ERC721 } from '../base/solady/ERC721.sol';
import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { NFTDescriptorV2 } from '../libs/NFTDescriptorV2.sol';
import { INounsDescriptorV2 } from '../interfaces/INounsDescriptorV2.sol';
import { INounsSeeder } from '../interfaces/INounsSeeder.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

interface INouns {
    function totalSupply() external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function seeds(uint256 tokenId) external view returns (INounsSeeder.Seed memory);

    function descriptor() external view returns (INounsDescriptorV2);
}

contract NounDelegationToken is ERC721 {
    using Strings for uint256;

    INouns nouns;
    string backgroundColor;
    mapping(address => address) public delegationAdmins;

    constructor(address nouns_, string memory backgroundColor_) {
        nouns = INouns(nouns_);
        backgroundColor = backgroundColor_;
    }

    /// @dev Returns the token collection name.
    function name() public pure virtual override returns (string memory) {
        return 'NounDelegationToken';
    }

    /// @dev Returns the token collection symbol.
    function symbol() public pure virtual override returns (string memory) {
        return 'NDT';
    }

    function mint(address to, uint256 tokenId) public {
        address nouner = nouns.ownerOf(tokenId);
        require(
            nouner == msg.sender || delegationAdmins[nouner] == msg.sender,
            'NounDelegationToken: Only Noun owner or their delegation admin can mint'
        );

        _mint(to, tokenId);
    }

    function mintBatch(address to, uint256[] calldata tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            mint(to, tokenIds[i]);
        }
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function setDelegationAdmin(address delegationAdmin) external {
        delegationAdmins[msg.sender] = delegationAdmin;
    }

    function ownerOfNoRevert(uint256 tokenId) external view returns (address) {
        if (_exists(tokenId)) return ownerOf(tokenId);
        return address(0);
    }

    function getTokenLastTransfer(uint256 tokenId) external view returns (uint96) {
        return _getExtraData(tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual override returns (bool) {
        address nouner = nouns.ownerOf(tokenId);
        if (nouner == spender || delegationAdmins[nouner] == spender) return true;

        return super._isApprovedOrOwner(spender, tokenId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        _setExtraData(tokenId, uint96(block.timestamp));
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory nounId = tokenId.toString();
        INounsDescriptorV2 descriptor = nouns.descriptor();

        NFTDescriptorV2.TokenURIParams memory params = NFTDescriptorV2.TokenURIParams({
            name: string(abi.encodePacked('Noun Delegation ', nounId)),
            description: string(
                abi.encodePacked(
                    'Noun Delegation ',
                    nounId,
                    ' allows its owner to participate in Nouns DAO on behalf of Noun ',
                    nounId
                )
            ),
            parts: descriptor.getPartsForSeed(nouns.seeds(tokenId)),
            background: backgroundColor
        });

        return NFTDescriptorV2.constructTokenURI(descriptor.renderer(), params);
    }
}
