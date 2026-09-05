import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AAVE_BORROW_TOPIC,
  AAVE_REPAY_TOPIC,
  AAVE_V3_POOL,
  MINIMUM_SELF_REPAYMENT_BLOCK_GAP,
  USDC,
  findReceiptLogOrdinal,
  matchSelfRepayments,
  parseAaveLog,
  parseOptions,
  parseWatchlist,
} from './leaderboard-watcher.mjs';

const SUBJECT = '0x1111111111111111111111111111111111111111';
const OTHER = '0x2222222222222222222222222222222222222222';
const hash = (byte) => `0x${byte.repeat(64)}`;
const topicFor = (address) => `0x${address.slice(2).padStart(64, '0')}`;
const word = (value) => value.toString(16).padStart(64, '0');

function eventLog({ kind, blockNumber, transactionIndex, logIndex, amount, repayer = SUBJECT }) {
  const borrowData = `0x${word(0x3333333333333333333333333333333333333333n)}${word(amount)}${word(2)}${word(0)}`;
  const repayData = `0x${word(amount)}${word(0)}`;
  return {
    address: AAVE_V3_POOL,
    topics: [
      kind === 'borrow' ? AAVE_BORROW_TOPIC : AAVE_REPAY_TOPIC,
      topicFor(USDC),
      topicFor(SUBJECT),
      kind === 'borrow' ? hash('0') : topicFor(repayer),
    ],
    data: kind === 'borrow' ? borrowData : repayData,
    transactionHash: hash(kind === 'borrow' ? 'a' : 'b'),
    blockNumber: `0x${blockNumber.toString(16)}`,
    transactionIndex: `0x${transactionIndex.toString(16)}`,
    logIndex: `0x${logIndex.toString(16)}`,
  };
}

test('parses a start-bounded public borrower watchlist', () => {
  assert.deepEqual(
    parseWatchlist(`${SUBJECT}@25854707,${OTHER}@25854708`),
    [
      { address: SUBJECT, startBlock: 25_854_707 },
      { address: OTHER, startBlock: 25_854_708 },
    ],
  );
  assert.throws(() => parseWatchlist(SUBJECT), /start block/);
});

test('uses a dry run unless --submit is explicit', () => {
  const options = parseOptions([], {
    CREDITCOIN_RPC_URL: 'https://cc3.example',
    CREDITCOIN_PROOF_BUILDER_URL: 'https://proof.example',
  });
  assert.equal(options.submit, false);
  assert.equal(options.watchlist.length, 0);
  assert.throws(
    () =>
      parseOptions(['--submit'], {
        CREDITCOIN_RPC_URL: 'https://cc3.example',
        CREDITCOIN_PROOF_BUILDER_URL: 'https://proof.example',
      }),
    /CREDITCOIN_PRIVATE_KEY/,
  );
});

test('decodes only the source fields the adapter later authenticates again', () => {
  const borrow = parseAaveLog(
    'borrow',
    SUBJECT,
    eventLog({ kind: 'borrow', blockNumber: 100, transactionIndex: 4, logIndex: 9, amount: 1_000n }),
  );
  const repay = parseAaveLog(
    'repay',
    SUBJECT,
    eventLog({ kind: 'repay', blockNumber: 140, transactionIndex: 2, logIndex: 8, amount: 1_100n }),
  );

  assert.equal(borrow.amount, 1_000n);
  assert.equal(repay.amount, 1_100n);
  assert.equal(repay.repayer, SUBJECT);
  assert.equal(borrow.blockNumber, 100);
});

test('matches a later, self-funded, same-or-larger repayment only once', () => {
  const borrow = parseAaveLog(
    'borrow',
    SUBJECT,
    eventLog({ kind: 'borrow', blockNumber: 100, transactionIndex: 1, logIndex: 1, amount: 1_000n }),
  );
  const tooSoon = parseAaveLog(
    'repay',
    SUBJECT,
    eventLog({
      kind: 'repay',
      blockNumber: 100 + MINIMUM_SELF_REPAYMENT_BLOCK_GAP - 1,
      transactionIndex: 1,
      logIndex: 2,
      amount: 1_000n,
    }),
  );
  const thirdParty = parseAaveLog(
    'repay',
    SUBJECT,
    eventLog({
      kind: 'repay',
      blockNumber: 140,
      transactionIndex: 1,
      logIndex: 3,
      amount: 1_000n,
      repayer: OTHER,
    }),
  );
  const eligible = parseAaveLog(
    'repay',
    SUBJECT,
    eventLog({ kind: 'repay', blockNumber: 141, transactionIndex: 1, logIndex: 4, amount: 1_000n }),
  );

  const matches = matchSelfRepayments([borrow], [tooSoon, thirdParty, eligible]);
  assert.equal(matches.length, 1);
  assert.equal(matches[0].repay.logIndex, eligible.logIndex);
});

test('finds the event ordinal within its own transaction receipt', () => {
  const candidate = parseAaveLog(
    'repay',
    SUBJECT,
    eventLog({ kind: 'repay', blockNumber: 140, transactionIndex: 2, logIndex: 42, amount: 1_000n }),
  );
  const receipt = {
    logs: [
      { logIndex: '0x28' },
      { logIndex: '0x2a' },
      { logIndex: '0x2c' },
    ],
  };
  assert.equal(findReceiptLogOrdinal(receipt, candidate), 1);
});
