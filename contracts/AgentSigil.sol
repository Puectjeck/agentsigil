// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AgentSigil
/// @notice A free daily sigil for Agent ID holders. Once per UTC day, a wallet
///         holding a SPACE ID Agent ID (name.ai) can call claim() to mint a
///         soulbound (non-transferable) ERC-721 sigil that records the
///         claimer's current streak (consecutive UTC days claimed), their
///         total claims, and the claim day, rendered as on-chain SVG metadata.
///         Missing a UTC day resets the streak to 1 on the next claim.
///
/// @dev OWNER POWERS (complete list — see README.md):
///        - The owner is NOT the deployer. The constructor takes an explicit
///          `initialOwner` address; the deployer (a burner EOA used only to
///          broadcast the creation transaction) holds NO power over this
///          contract after deployment and cannot regain any.
///        - pause() / unpause(): the owner (initialOwner) can pause and
///          unpause claims as a safety measure. That is the ONLY owner power.
///        - There is NO owner mint, NO withdraw function (the contract holds
///          no funds and claim() is free / non-payable), NO proxy and NO
///          upgradeability. The Agent ID contract address is immutable.
///          Ownership itself is not transferable (no transfer function).
///
///      SOULBOUND: all transfer and approval functions revert. Tokens can
///      never leave the wallet that claimed them (mint is the only Transfer).
///
///      Agent ID gate: claim() and stateOf() call balanceOf(address) on the
///      SPACE ID Agent ID contract at 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F
///      (BNB Smart Chain). balanceOf(user) > 0 means the user holds an Agent ID.

interface IAgentId {
    function balanceOf(address owner) external view returns (uint256);
}

contract AgentSigil {
    // ------------------------------------------------------------------ //
    // ERC-721 metadata
    // ------------------------------------------------------------------ //
    string public constant name = "AgentSigil";
    string public constant symbol = "SIGIL";

    // ------------------------------------------------------------------ //
    // State
    // ------------------------------------------------------------------ //
    IAgentId public constant AGENT_ID =
        IAgentId(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);

    address public owner;
    bool public paused;

    uint256 private _nextTokenId = 1;
    uint256 private _totalClaims;
    uint256 private _uniqueClaimers;

    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _owners;

    mapping(address => uint256) public lastClaimDay; // UTC day index of last claim
    mapping(address => uint256) public streakOf;     // stored streak (see stateOf for effective)
    mapping(address => uint256) public totalClaimsOf;

    // Per-token snapshot taken at mint time.
    mapping(uint256 => uint256) public tokenDay;
    mapping(uint256 => uint256) public tokenStreak;
    mapping(uint256 => uint256) public tokenTotalClaims;

    // ------------------------------------------------------------------ //
    // Events
    // ------------------------------------------------------------------ //
    event Claimed(address indexed user, uint256 indexed tokenId, uint256 day, uint256 streak);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Locked(uint256 tokenId); // ERC-5192: emitted at mint; sigils are locked from birth
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    // ------------------------------------------------------------------ //
    // Constructor / owner safety switch
    // ------------------------------------------------------------------ //
    /// @param initialOwner The address that holds the pause/unpause power.
    ///        Deliberately separate from the deployer: at production deploy
    ///        time this is Jon's Binance Agentic Wallet
    ///        (0x4A5944DDf10C5426C39b20b059e340b4E81a98b6), which can then call
    ///        pause()/unpause() via `baw contract-call`. The deploying
    ///        burner EOA gets no rights whatsoever.
    constructor(address initialOwner) {
        require(initialOwner != address(0), "zero owner");
        owner = initialOwner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /// @notice Pause claims (safety only; does not affect existing tokens).
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause claims.
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // ------------------------------------------------------------------ //
    // Core: daily claim
    // ------------------------------------------------------------------ //
    function _today() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /// @notice Claim today's sigil. Free. Requires holding an Agent ID.
    ///         One claim per wallet per UTC day. Mint is the only way a
    ///         token comes into existence, and it always goes to msg.sender.
    function claim() external returns (uint256 tokenId) {
        require(!paused, "claims paused");
        require(AGENT_ID.balanceOf(msg.sender) > 0, "no Agent ID");
        uint256 today = _today();
        require(
            totalClaimsOf[msg.sender] == 0 || lastClaimDay[msg.sender] < today,
            "already claimed today"
        );

        // Streak continues only if the previous claim was yesterday.
        // (today > 0 is checked first so today - 1 can never underflow;
        // on BSC today is always >> 0 anyway.)
        uint256 newStreak = 1;
        if (today > 0 && lastClaimDay[msg.sender] == today - 1) {
            newStreak = streakOf[msg.sender] + 1;
        }

        if (totalClaimsOf[msg.sender] == 0) {
            _uniqueClaimers += 1;
        }
        streakOf[msg.sender] = newStreak;
        totalClaimsOf[msg.sender] += 1;
        lastClaimDay[msg.sender] = today;
        _totalClaims += 1;

        tokenId = _nextTokenId++;
        _owners[tokenId] = msg.sender;
        _balances[msg.sender] += 1;
        tokenDay[tokenId] = today;
        tokenStreak[tokenId] = newStreak;
        tokenTotalClaims[tokenId] = totalClaimsOf[msg.sender];

        emit Transfer(address(0), msg.sender, tokenId);
        emit Locked(tokenId);
        emit Claimed(msg.sender, tokenId, today, newStreak);
    }

    // ------------------------------------------------------------------ //
    // View helpers (frontend)
    // ------------------------------------------------------------------ //
    /// @notice One-call state for the frontend.
    /// @return hasAgentId    wallet currently holds an Agent ID
    /// @return claimedToday  wallet already claimed on the current UTC day
    /// @return streak        effective streak (0 if the streak has lapsed)
    /// @return totalClaims   lifetime claims by this wallet
    /// @return nextClaimTime unix time the next claim unlocks on the day
    ///         boundary (the current time when no day-wait applies). This is
    ///         the day-boundary signal only: callers must ALSO check
    ///         hasAgentId and the public `paused` flag before offering a claim.
    function stateOf(address user)
        external
        view
        returns (
            bool hasAgentId,
            bool claimedToday,
            uint256 streak,
            uint256 totalClaims,
            uint256 nextClaimTime
        )
    {
        uint256 today = _today();
        hasAgentId = AGENT_ID.balanceOf(user) > 0;
        claimedToday = (lastClaimDay[user] == today && totalClaimsOf[user] > 0);
        totalClaims = totalClaimsOf[user];
        if (
            totalClaims > 0 &&
            (lastClaimDay[user] == today || (today > 0 && lastClaimDay[user] == today - 1))
        ) {
            streak = streakOf[user];
        } else {
            streak = 0;
        }
        nextClaimTime = claimedToday ? (today + 1) * 1 days : block.timestamp;
    }

    function totalClaims() external view returns (uint256) {
        return _totalClaims;
    }

    function uniqueClaimers() external view returns (uint256) {
        return _uniqueClaimers;
    }

    function totalSupply() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    // ------------------------------------------------------------------ //
    // Minimal ERC-721 surface (soulbound)
    // ------------------------------------------------------------------ //
    function balanceOf(address account) external view returns (uint256) {
        require(account != address(0), "zero address");
        return _balances[account];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "nonexistent token");
        return o;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f || // ERC721Metadata
            interfaceId == 0xb45a3c0e;   // ERC5192 (soulbound signaling)
    }

    /// @notice ERC-5192: every AgentSigil is permanently locked (soulbound).
    function locked(uint256 tokenId) external view returns (bool) {
        require(_owners[tokenId] != address(0), "nonexistent token");
        return true;
    }

    // Soulbound: every transfer / approval path reverts.
    function transferFrom(address, address, uint256) external pure {
        revert("soulbound");
    }

    function safeTransferFrom(address, address, uint256) external pure {
        revert("soulbound");
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert("soulbound");
    }

    function approve(address, uint256) external pure {
        revert("soulbound");
    }

    function setApprovalForAll(address, bool) external pure {
        revert("soulbound");
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_owners[tokenId] != address(0), "nonexistent token");
        return address(0);
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    // ------------------------------------------------------------------ //
    // On-chain metadata (SVG)
    // ------------------------------------------------------------------ //
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_owners[tokenId] != address(0), "nonexistent token");
        uint256 streak = tokenStreak[tokenId];
        uint256 total = tokenTotalClaims[tokenId];
        uint256 day = tokenDay[tokenId];

        string memory svg = string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' width='400' height='400' viewBox='0 0 400 400'>",
                "<rect width='400' height='400' fill='#0b0e17'/>",
                "<circle cx='200' cy='150' r='95' fill='none' stroke='#f0b90b' stroke-width='6'/>",
                "<text x='200' y='140' font-family='monospace' font-size='26' fill='#f0b90b' text-anchor='middle'>AgentSigil</text>",
                "<text x='200' y='185' font-family='monospace' font-size='44' fill='#ffffff' text-anchor='middle'>",
                _toString(streak),
                "</text>",
                "<text x='200' y='215' font-family='monospace' font-size='15' fill='#9aa4b2' text-anchor='middle'>day streak</text>",
                "<text x='200' y='300' font-family='monospace' font-size='17' fill='#ffffff' text-anchor='middle'>Total claims: ",
                _toString(total),
                "</text>",
                "<text x='200' y='330' font-family='monospace' font-size='15' fill='#9aa4b2' text-anchor='middle'>UTC day ",
                _toString(day),
                "</text>",
                "<text x='200' y='368' font-family='monospace' font-size='12' fill='#9aa4b2' text-anchor='middle'>Sigil #",
                _toString(tokenId),
                " - soulbound</text>",
                "</svg>"
            )
        );

        string memory json = string(
            abi.encodePacked(
                '{"name":"AgentSigil #',
                _toString(tokenId),
                '","description":"A soulbound daily sigil for Agent ID holders. One claim per UTC day; the sigil records the claim streak at mint time.",',
                '"attributes":[{"trait_type":"Streak","value":',
                _toString(streak),
                '},{"trait_type":"Total Claims","value":',
                _toString(total),
                '},{"trait_type":"UTC Day","value":',
                _toString(day),
                '}],"image":"data:image/svg+xml;base64,',
                _base64(bytes(svg)),
                '"}'
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", _base64(bytes(json))));
    }

    // ------------------------------------------------------------------ //
    // Small helpers
    // ------------------------------------------------------------------ //
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    bytes internal constant _B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @dev Plain-Solidity Base64 encoder (no assembly). Only used inside
    ///      tokenURI(), which is a view — runtime cost here is off-chain.
    function _base64(bytes memory data) internal pure returns (string memory) {
        uint256 len = data.length;
        if (len == 0) return "";
        uint256 encLen = 4 * ((len + 2) / 3);
        bytes memory result = new bytes(encLen);
        uint256 j = 0;
        for (uint256 i = 0; i < len; i += 3) {
            uint256 a = uint8(data[i]);
            uint256 b = i + 1 < len ? uint8(data[i + 1]) : 0;
            uint256 c = i + 2 < len ? uint8(data[i + 2]) : 0;
            uint256 n = (a << 16) | (b << 8) | c;
            result[j++] = _B64[(n >> 18) & 63];
            result[j++] = _B64[(n >> 12) & 63];
            result[j++] = _B64[(n >> 6) & 63];
            result[j++] = _B64[n & 63];
        }
        uint256 rem = len % 3;
        if (rem == 1) {
            result[encLen - 2] = "=";
            result[encLen - 1] = "=";
        } else if (rem == 2) {
            result[encLen - 1] = "=";
        }
        return string(result);
    }
}
