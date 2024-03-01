// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { BitMaps } from '@openzeppelin/contracts/utils/structs/BitMaps.sol';

library VotingBitMaps {
    using BitMaps for BitMaps.BitMap;

    /**
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * 2 bits are saved:
     * 00 - Not voted
     * 01 - Against
     * 10 - For
     * 11 - Abstain
     */
    function setVoting(BitMaps.BitMap storage bitmap, uint256 tokenId, uint8 support) internal {
        require(support <= 2);
        support += 1; // Shift support to 1-3 range

        bitmap.setTo(tokenId * 2, support & 1 == 1);
        bitmap.setTo(tokenId * 2 + 1, support >> 1 == 1);
    }

    function getVoting(
        BitMaps.BitMap storage bitmap,
        uint256 tokenId
    ) internal view returns (bool hasVoted, uint8 support) {
        uint8 bit0 = bitmap.get(tokenId * 2) ? 1 : 0;
        uint8 bit1 = bitmap.get(tokenId * 2 + 1) ? 1 : 0;
        support += bit0;
        support += bit1 << 1;

        hasVoted = support != 0;
        if (hasVoted) {
            support -= 1; // Shift support to 0-2 range
        }
    }
}
