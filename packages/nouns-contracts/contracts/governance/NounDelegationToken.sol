// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { ERC721Enumerable } from '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import { ERC721 } from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
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

contract NounDelegationToken is ERC721Enumerable {
    using Strings for uint256;

    INouns nouns;
    string backgroundColor;
    mapping(address => address) public delegationAdmins;

    constructor(address nouns_, string memory backgroundColor_) ERC721('NounDelegationToken', 'NDT') {
        nouns = INouns(nouns_);
        backgroundColor = backgroundColor_;
    }

    function mint(address to, uint256 tokenId) public {
        address nouner = nouns.ownerOf(tokenId);
        require(
            nouner == msg.sender || delegationAdmins[nouner] == msg.sender,
            'NounDelegationToken: Only Noun owner or their delegation admin can mint'
        );

        _safeMint(to, tokenId);
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

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual override returns (bool) {
        address nouner = nouns.ownerOf(tokenId);
        if (nouner == spender || delegationAdmins[nouner] == spender) return true;

        return super._isApprovedOrOwner(spender, tokenId);
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
