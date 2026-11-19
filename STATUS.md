# AgentSigil — build status

**Date:** 2026-11-19 · **State: DEPLOYED + Sourcify-verified (exact match).**

## Deployment record (2026-11-19 ~12:29 WIB)

- **Contract:** `0x57cA622dCadFd2fD02439ac8C24Ff7f96332A025` (BNB Smart Chain)
- **Deploy tx:** `0xafd98ffd80a4fade8ce7857573bc36c7c619633e64a33b7dc096345815a89baf`
  — status 0x1, block 134447328, gasUsed 1,533,068 @ 0.05 gwei
  = **0.0000766534 BNB** actual cost.
- **Deployer:** Set 1 EOA `0x1F1Cb24B014Ff409d592558D69358FF4DCbfDBe4`
  (funded exactly 0.0002 BNB by Jon; remaining balance after deploy
  **0.0001233466 BNB**).
- **Read-backs verified on-chain:** `owner()` =
  `0x4A5944DDf10C5426C39b20b059e340b4E81a98b6` (Jon's Agentic Wallet, NOT
  the deployer) · `name()` = AgentSigil · `symbol()` = SIGIL ·
  `paused()` = false · `stateOf(Jon)`: hasAgentId=true, claimedToday=false,
  streak=0, totalClaims=0.
- **Source verification:** Sourcify (chain 56) — **exact_match** for both
  creation and runtime bytecode (matchId 59508443, verified
  2026-11-19T05:31:31Z), solc 0.8.38+commit.1835d247, viaIR, optimizer 200.
  **BscScan verification: pending API key** (BscScan API requires a key we
  don't have; no account created).
- **First interaction already happened organically:** an external Agent ID
  holder `0x072c7A43e7e81350734A48EF5A117e6a1E98E331` (Agent ID balance
  verified = 1) claimed token #1 shortly after deployment —
  `ownerOf(1)` = that address, tokenDay = today (20776), streak 1,
  totalClaims/uniqueClaimers = 1. The gate works as designed; no claim was
  made by Jon, Adek, or the deployer.
- Placeholders filled: `CONTRACT_ADDRESS` in `app/index.html`, contract
  address in the README submission fields.

## Public repository, website, and submission channel (2026-11-19)

- **Intended public repository:** https://github.com/Puectjeck/agentsigil
  — **NOT CREATED.** On 2026-11-19 the GitHub connector's
  `create_repository` call was approved but GitHub returned
  `403 Resource not accessible by integration`; a follow-up repository
  lookup returned 404. No project files were pushed.
- **Intended website:** https://puectjeck.github.io/agentsigil/
  — **NOT LIVE.** The required `Puectjeck/Puectjeck.github.io` repository
  also did not exist (lookup 404). A later connector approval request to
  create that repository expired before approval, so that action was not
  performed and was not retried. Fetching the intended website URL on
  2026-11-19 returned HTTP 404, so the contract address could not be
  verified on a live page.
- **Official submission channel research:** Binance's official announcement
  (https://www.binance.com/en/support/announcement/detail/95f5dbe0ea674a48a739b59e046648bf)
  says to submit the project name, website, contract address(es), Agent ID
  usage description, and other required materials during 2026-11-18
  08:00 UTC → 2026-12-09 08:00 UTC, with no registration needed. As of
  2026-11-19, neither that announcement nor official-channel web search
  exposed a separate public project-submission form URL. The announcement's
  only linked survey resolves to
  https://app.binance.com/uni-qr/user-survey/ff6832f8d2984af289068c9450a3c98c
  and its text is specifically for submitting an X link for the Community
  Promotion Award — **not** a project-submission form. Nothing has been
  submitted yet.

## What was built

| Deliverable | Status |
|---|---|
| `contracts/AgentSigil.sol` | ✅ Hand-rolled soulbound ERC-721, no dependencies. Daily `claim()` gated on Agent ID `balanceOf > 0`, streak/total/day snapshots, on-chain SVG `tokenURI`, `stateOf()` + counters, ERC-5192 `locked()`. |
| Owner model | ✅ **Changed per Jon's design call:** `constructor(address initialOwner)` — deployer gets zero powers; owner (pause/unpause only) will be Jon's Agentic Wallet `0x4A5944DDf10C5426C39b20b059e340b4E81a98b6` at deploy time. Documented in contract header + README. |
| Compile | ✅ solc-js, solc **0.8.38**, viaIR on, optimizer 200 runs. Artifact: `build/AgentSigil.json`. |
| Frontend `app/index.html` | ✅ One static file; ethers v6 CDN; visitor's own wallet; reads `stateOf()`/`paused()`/counters; countdown; Claim button; `CONTRACT_ADDRESS` placeholder marked TO FILL AFTER DEPLOY; how-it-works + owner-permissions sections; no QR login, no return promises. |
| `README.md` | ✅ Description, Agent ID usage, owner permissions, red-line compliance, build + deploy + Sourcify/BscScan verify steps, pre-drafted submission fields. |
| `scripts/deploy.js` | ✅ Template for the main session; refuses to run without `CONFIRM_DEPLOY=YES` + env-only key. **Not run.** |
| Codex review | ✅ Done — see below and `build/codex-review.md`. |

## Compile result (final, after all fixes)

- Creation bytecode: **6,818 bytes**
- Deployed bytecode: **6,623 bytes**
- Estimated deployment gas: **1,511,424** (≈ **0.0000756 BNB** at 0.05 gwei)
  — inside the ~2M-gas target and the ~0.0002 BNB deployer budget.
- One benign warning: named return `totalClaims` in `stateOf()` shadows the
  `totalClaims()` function name (name-only; values verified correct).

Build history worth knowing: the first compile failed with "stack too deep"
(two rounds — assembly Base64, then packed `tokenURI` strings). Fixed by
(1) replacing the assembly Base64 with a plain-Solidity encoder and
(2) enabling `viaIR` — the final settings are recorded in
`build/AgentSigil.json` and the README verification table.

## Codex review outcome

Ran successfully on the first attempt this session (no HTTP 429).
Headline: **no mint bypass, no same-day double claim, no transfer path
found**; streak/day logic, Base64/SVG/JSON all verified correct; only
`initialOwner` can pause/unpause; deployment grants no privileges.
Three findings, all Low/Informational:

1. `stateOf().nextClaimTime` is a day-boundary signal only (ignores pause /
   Agent ID) → documented on the function; frontend checks `paused()` and
   `hasAgentId` separately and disables Claim with a clear message.
2. Claim/state depend on the official Agent ID contract's `balanceOf`
   (STATICCALL, no reentrancy path) → accepted; it is the hackathon's own
   registry and the product's core gate.
3. No ERC-5192 soulbound signaling → **fixed**: added `locked()`, `Locked`
   event, and interface id `0xb45a3c0e`; recompiled (numbers above are
   post-fix).

Full record: `build/codex-review.md`.

## Remaining steps (main session + Jon)

1. ✅ Deployer top-up, deploy, `owner()` read-back, Sourcify verification —
   done 2026-11-19 (see deployment record above). BscScan verification
   still pending an API key.
2. **Create the public GitHub repository + GitHub Pages user-site
   repository manually or grant the GitHub integration permission to
   create/access them, then push the prepared files.** The connector
   attempt failed as recorded above; the intended URLs currently return
   404.
3. **Test claim from Jon's Agentic Wallet** (deliberately NOT done by the
   deploy run) + Adek's wallet — first-party claims still outstanding.
4. **Submit** to the hackathon before 2026-12-09 08:00 UTC, using the
   official channel recorded above if Binance publishes/confirms the
   project-intake route; the linked survey found so far is promotion-only.
5. **Innovation Award eligibility needs ≥30 distinct Agent ID addresses**
   interacting during 2026-11-18 → 2026-12-09 — 1 organic claim so far;
   community promotion has to happen after launch.
